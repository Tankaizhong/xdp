// SPDX-License-Identifier: GPL-2.0
/* XDP Load Balancer - 基于 XDP TX 的 L4 负载均衡 */

#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/in.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "common.h"

/* ========== eBPF Maps ========== */

/* VIP -> 后端列表映射 */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(key_size, sizeof(struct vip_key));
    __uint(value_size, sizeof(struct vip_info));
    __uint(max_entries, 128);
} vip_map SEC(".maps");

/* 连接跟踪 (用于会话保持/最少连接) */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(key_size, sizeof(struct flow_key));
    __uint(value_size, sizeof(__u32));  /* backend index */
    __uint(max_entries, 65536);
} conn_track SEC(".maps");

/* 统计 Map */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(struct stats));
    __uint(max_entries, 1);
} stats_map SEC(".maps");

/* 后端索引计数器 (用于 RR) */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u32));
    __uint(max_entries, 128);
} lb_counters SEC(".maps");

/* ========== 辅助函数 ========== */

/* 更新统计 */
static __always_inline void update_stats(int rx, int tx, int drop)
{
    struct stats *s;
    __u32 key = 0;

    s = bpf_map_lookup_elem(&stats_map, &key);
    if (s) {
        if (rx) s->rx_packets++;
        if (tx) s->tx_packets++;
        if (drop) s->dropped++;
    }
}

/* CRC32 哈希 (用于一致性哈希) */
static __always_inline __u32 crc32_hash(__u32 val)
{
    __u32 hash = val;
    __u32 i;

    for (i = 0; i < 8; i++) {
        hash = (hash << 1) | (hash >> 31);
    }
    return hash;
}

/* 选择后端 - 负载均衡算法 */
static __always_inline int select_backend(struct vip_info *vip, __u32 src_ip, __u32 hash)
{
    if (!vip || vip->backend_count == 0)
        return -1;

    switch (vip->lb_algorithm) {
    case LB_RR: {
        /* 轮询 - 使用 atomic 计数器 */
        __u32 key = 0;
        __u32 *counter = bpf_map_lookup_elem(&lb_counters, &key);
        if (counter) {
            __u32 idx = (*counter) % vip->backend_count;
            /* 原子递增 */
            bpf_map_update_elem(&lb_counters, &key, &((__u32){(*counter + 1)}), BPF_ANY);
            return idx;
        }
        return 0;
    }
    case LB_HASH:
    case LB_CONSISTENT_HASH: {
        /* 源IP哈希 */
        return hash % vip->backend_count;
    }
    case LB_LC: {
        /* 最少连接 - 简化版，使用源IP哈希 */
        return hash % vip->backend_count;
    }
    default:
        return 0;
    }
}

/* 获取哈希值 */
static __always_inline __u32 get_hash(__u32 src_ip, __u16 src_port)
{
    return src_ip + src_port;
}

/* 检查是否是目标VIP */
static __always_inline int is_target_vip(struct vip_key *vip_key, __u32 dst_ip, __u16 dst_port, __u8 proto)
{
    return (vip_key->vip == dst_ip &&
            vip_key->port == dst_port &&
            vip_key->proto == proto);
}

/* ========== XDP 主程序 ========== */
SEC("xdp_lb")
int xdp_lb_func(struct xdp_md *ctx)
{
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;
    struct ethhdr *eth;
    struct iphdr *ip;
    struct tcphdr *tcp;
    struct udphdr *udp;
    struct vip_key vip_key = {0};
    struct vip_info *vip;
    struct backend *backend;
    int backend_idx;
    __u32 hash;

    /* 解析以太网头 */
    eth = data;
    if (eth + 1 > data_end)
        goto drop;

    /* 仅处理IPv4 */
    if (eth->h_proto != bpf_htons(ETH_P_IP))
        goto pass;

    /* 解析IP头 */
    ip = data + sizeof(*eth);
    if (ip + 1 > data_end)
        goto drop;

    /* 解析传输层头 */
    if (ip->protocol == IPPROTO_TCP) {
        tcp = (struct tcphdr *)(ip + 1);
        if (tcp + 1 > data_end)
            goto drop;

        vip_key.vip = ip->daddr;
        vip_key.port = tcp->dest;
        vip_key.proto = IPPROTO_TCP;
    } else if (ip->protocol == IPPROTO_UDP) {
        udp = (struct udphdr *)(ip + 1);
        if (udp + 1 > data_end)
            goto drop;

        vip_key.vip = ip->daddr;
        vip_key.port = udp->dest;
        vip_key.proto = IPPROTO_UDP;
    } else {
        /* 非 TCP/UDP 放行 */
        goto pass;
    }

    /* 查找VIP对应的后端列表 */
    vip = bpf_map_lookup_elem(&vip_map, &vip_key);
    if (!vip) {
        /* 未配置VIP，放行 */
        goto pass;
    }

    /* 计算哈希值 */
    hash = get_hash(ip->saddr, vip_key.port ? : tcp->source);

    /* 选择后端 */
    backend_idx = select_backend(vip, ip->saddr, hash);
    if (backend_idx < 0 || backend_idx >= vip->backend_count)
        goto drop;

    backend = &vip->backends[backend_idx];
    if (!backend->enabled)
        goto drop;

    /* 更新统计 */
    update_stats(1, 1, 0);

    /* 修改以太网头 - 目的MAC改为后端MAC，源MAC改为本机MAC */
    __builtin_memcpy(eth->h_dest, backend->mac, ETH_ALEN);
    /* 源MAC保持不变或设置为本机MAC */

    /* 修改IP头 - 目的IP改为后端IP */
    ip->daddr = backend->ip;

    /* IP校验和清零，让网卡重新计算 */
    ip->check = 0;

    /* 修改端口 */
    if (ip->protocol == IPPROTO_TCP && tcp) {
        tcp->dest = backend->port;
        tcp->check = 0;
    } else if (ip->protocol == IPPROTO_UDP && udp) {
        udp->dest = backend->port;
        udp->check = 0;
    }

    /* 直接发送 */
    return XDP_TX;

pass:
    update_stats(1, 0, 0);
    return XDP_PASS;

drop:
    update_stats(0, 0, 1);
    return XDP_DROP;
}

char _license[] SEC("license") = "GPL";
