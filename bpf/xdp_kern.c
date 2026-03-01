// SPDX-License-Identifier: GPL-2.0
/* XDP Cluster Forwarding - 基于五元组的哈希查表转发 */

#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/in.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <bpf/bpf_helpers.h>
#include <xdp/parsing_helpers.h>
#include "../src/common/common.h"

/* 使用 xdp-tools 的 SEC 宏定义 MAP */
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(key_size, sizeof(struct flow_key));
	__uint(value_size, sizeof(struct forward_entry));
	__uint(max_entries, MAP_SIZE);
} flow_table SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(key_size, sizeof(__u32));
	__uint(value_size, sizeof(struct stats));
	__uint(max_entries, 1);
} stats_map SEC(".maps");

/* 提取五元组并查表 */
static __always_inline struct forward_entry* flow_lookup(struct xdp_md *ctx,
						       struct flow_key *key)
{
	void *data_end = (void *)(long)ctx->data_end;
	void *data = (void *)(long)ctx->data;
	struct ethhdr *eth = data;
	struct iphdr *ip;
	struct tcphdr *tcp;
	struct udphdr *udp;

	/* 检查以太网头 */
	if (data + sizeof(*eth) > data_end)
		return NULL;

	/* 仅处理IPv4 */
	if (eth->h_proto != bpf_htons(ETH_P_IP))
		return NULL;

	ip = data + sizeof(*eth);
	if (ip + 1 > data_end)
		return NULL;

	/* 填充五元组 */
	key->src_ip = ip->saddr;
	key->dst_ip = ip->daddr;
	key->proto = ip->protocol;

	/* 提取传输层端口 */
	if (ip->protocol == IPPROTO_TCP) {
		tcp = (struct tcphdr *)(ip + 1);
		if (tcp + 1 > data_end)
			return NULL;
		key->src_port = tcp->source;
		key->dst_port = tcp->dest;
	} else if (ip->protocol == IPPROTO_UDP) {
		udp = (struct udphdr *)(ip + 1);
		if (udp + 1 > data_end)
			return NULL;
		key->src_port = udp->source;
		key->dst_port = udp->dest;
	} else {
		key->src_port = 0;
		key->dst_port = 0;
	}

	/* O(1) 哈希查表 */
	return bpf_map_lookup_elem(&flow_table, key);
}

/* 更新统计信息 */
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

/* XDP 主程序 */
SEC("xdp")
int xdp_forward(struct xdp_md *ctx)
{
	void *data_end = (void *)(long)ctx->data_end;
	void *data = (void *)(long)ctx->data;
	struct flow_key key = {0};
	struct forward_entry *entry;
	struct ethhdr *eth;
	struct iphdr *ip;

	/* 提取五元组并查表 */
	entry = flow_lookup(ctx, &key);
	if (!entry) {
		/* 未找到匹配规则，透传至内核协议栈 */
		update_stats(1, 0, 0);
		return XDP_PASS;
	}

	/* 更新统计 */
	update_stats(1, 0, 0);

	eth = data;
	if (eth + 1 > data_end)
		return XDP_DROP;

	/* 原地修改目的MAC地址 */
	if (entry->action == XDP_ACTION_TX) {
		__u8 orig_dst[ETH_ALEN];

		/* 保存原始目的MAC */
		__builtin_memcpy(orig_dst, eth->h_dest, ETH_ALEN);

		/* 设置新的目的MAC */
		__builtin_memcpy(eth->h_dest, entry->dst_mac, ETH_ALEN);
		/* 交换源和目的MAC（类似桥接） */
		__builtin_memcpy(eth->h_source, orig_dst, ETH_ALEN);

		/* 修改IP地址 */
		ip = data + sizeof(*eth);
		if (ip + 1 <= data_end) {
			ip->daddr = entry->dst_ip;
			/* 重新计算IP校验和 */
			ip->check = 0;
		}

		update_stats(0, 1, 0);
		return XDP_TX;
	}

	/* 默认丢弃 */
	update_stats(0, 0, 1);
	return XDP_DROP;
}

char _license[] SEC("license") = "GPL";
