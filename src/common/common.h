/* common.h - XDP 集群转发通用定义 */

#ifndef _COMMON_H
#define _COMMON_H

#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <linux/udp.h>
#include <linux/tcp.h>

/* eBPF Map 定义 */
#define MAP_SIZE 1024
#define MAX_BACKENDS 16

/* 负载均衡算法 */
#define LB_RR 0      /* 轮询 */
#define LB_HASH 1    /* 源IP哈希 */
#define LB_LC 2      /* 最少连接 */
#define LB_CONSISTENT_HASH 3  /* 一致性哈希 */

/* ========== 负载均衡相关结构 ========== */

/* VIP (虚拟IP) 配置 */
struct vip_key {
    __u32 vip;        /* 虚拟IP */
    __u16 port;       /* 虚拟端口 */
    __u8  proto;      /* 协议 (TCP/UDP) */
};

/* 后端服务器信息 */
struct backend {
    __u32 ip;         /* 后端IP */
    __u16 port;       /* 后端端口 */
    __u8  mac[ETH_ALEN];  /* 后端MAC */
    __u8  weight;     /* 权重 */
    __u8  enabled;    /* 是否启用 */
};

/* VIP 对应的后端列表 */
struct vip_info {
    struct backend backends[MAX_BACKENDS];
    __u8 backend_count;
    __u8 lb_algorithm;     /* 负载均衡算法 */
};

/* 连接跟踪 (用于最少连接) */
struct connection {
    __u32 src_ip;
    __u16 src_port;
    __u8  proto;
    __u8  padding;
    __u32 backend_idx;    /* 选中的后端索引 */
    __u32 conn_count;     /* 连接数 */
};

/* ========== 原有结构 (保留兼容) ========== */

/* 转发规则 Map */
struct flow_key {
    __u32 src_ip;
    __u32 dst_ip;
    __u16 src_port;
    __u16 dst_port;
    __u8  proto;
};

struct forward_entry {
    __u8  dst_mac[ETH_ALEN];  /* 目标MAC地址 */
    __u32 dst_ip;      /* 目标IP地址 */
    __u8  action;      /* 转发动作 */
};

/* 统计 Map */
struct stats {
    __u64 rx_packets;
    __u64 tx_packets;
    __u64 dropped;
    __u64 parse_err;
};

/* 动作定义 */
#define XDP_ACTION_DROP   0
#define XDP_ACTION_PASS   1
#define XDP_ACTION_TX     2
#define XDP_ACTION_REDIRECT 3

/* 默认队列和端口配置 */
#define DEFAULT_QUEUE_ID 0
#define AF_XDP_FLAGS     0

#endif /* _COMMON_H */
