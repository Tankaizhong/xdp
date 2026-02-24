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

/* 转发规则 Map */
struct flow_key {
    __u32 src_ip;
    __u32 dst_ip;
    __u16 src_port;
    __u16 dst_port;
    __u8  proto;
};

struct forward_entry {
    __u32 dst_mac[2];  /* 目标MAC地址 */
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
