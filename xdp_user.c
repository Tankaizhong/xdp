/* xdp_user.c - XDP 用户态控制面程序
 * 使用 libxdp API
 * 实现eBPF Map管理、AF_XDP通信和统计查询
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/socket.h>
#include <linux/if_link.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <xdp/libxdp.h>
#include <bpf/bpf.h>
#include "common.h"

#define IFACE_NAME "eth0"
#define BPF_OBJ_FILE "xdp_kern.o"

/* 全局变量 */
static int ifindex = -1;
static int prog_fd = -1;
static int map_fd = -1;
static int stats_fd = -1;
static struct xdp_program *xdp_prog = NULL;
static volatile int running = 1;

/* 信号处理 */
static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* 加载 XDP 程序 - 使用新版 libxdp API */
static int load_xdp_program(const char *filename)
{
    /* 使用 libxdp 打开并加载 XDP 程序 */
    xdp_prog = xdp_program__open_file(filename, "xdp", NULL);
    if (!xdp_prog) {
        fprintf(stderr, "Error: Failed to open XDP program: %s\n", strerror(errno));
        return -1;
    }

    /* 获取程序 fd - 新版直接可用，无需 xdp_program__load */
    prog_fd = xdp_program__fd(xdp_prog);
    if (prog_fd < 0) {
        fprintf(stderr, "Error: Failed to get program fd\n");
        return -1;
    }

    /* 获取 bpf_object 以访问 maps */
    struct bpf_object *bpf_obj = xdp_program__bpf_obj(xdp_prog);
    if (!bpf_obj) {
        fprintf(stderr, "Error: Failed to get bpf_object\n");
        return -1;
    }

    /* 查找 flow_table map - 使用 bpf_map__for_each 宏 */
    struct bpf_map *map = NULL;
    bpf_map__for_each(map, bpf_obj) {
        if (strcmp(bpf_map__name(map), "flow_table") == 0) {
            map_fd = bpf_map__fd(map);
            break;
        }
    }
    if (map_fd < 0) {
        fprintf(stderr, "Error: Failed to get flow_table map fd\n");
        return -1;
    }

    /* 查找 stats_map */
    map = NULL;
    bpf_map__for_each(map, bpf_obj) {
        if (strcmp(bpf_map__name(map), "stats_map") == 0) {
            stats_fd = bpf_map__fd(map);
            break;
        }
    }
    if (stats_fd < 0) {
        fprintf(stderr, "Error: Failed to get stats_map map fd\n");
        return -1;
    }

    printf("[+] XDP program loaded successfully\n");
    return 0;
}

/* 附加 XDP 到网卡 - 使用 libxdp API */
static int attach_xdp(const char *ifname)
{
    int err;

    ifindex = if_nametoindex(ifname);
    if (!ifindex) {
        fprintf(stderr, "Error: Interface %s not found\n", ifname);
        return -1;
    }

    if (!xdp_prog) {
        fprintf(stderr, "Error: XDP program not loaded\n");
        return -1;
    }

    /* 使用 libxdp 附加程序 */
    err = xdp_program__attach(xdp_prog, ifindex, XDP_MODE_NATIVE, 0);
    if (err < 0) {
        /* 尝试通用模式 */
        err = xdp_program__attach(xdp_prog, ifindex, XDP_MODE_SKB, 0);
        if (err < 0) {
            fprintf(stderr, "Error: Failed to attach XDP to %s: %s\n",
                    ifname, strerror(errno));
            return -1;
        }
        printf("[+] XDP attached to %s (SKB mode)\n", ifname);
    } else {
        printf("[+] XDP attached to %s (Native mode)\n", ifname);
    }

    return 0;
}

/* 分离 XDP */
static void detach_xdp(void)
{
    if (xdp_prog && ifindex > 0) {
        /* 使用 libxdp 分离程序 */
        xdp_program__detach(xdp_prog, ifindex, XDP_MODE_NATIVE, 0);
        printf("[*] XDP detached from interface\n");
    }
}

/* 添加转发规则 */
static int add_flow_rule(__u32 src_ip, __u32 dst_ip,
                         __u16 src_port, __u16 dst_port,
                         __u8 proto, __u8 *mac, __u32 new_dst_ip,
                         __u8 action)
{
    struct flow_key key = {0};
    struct forward_entry entry = {0};
    int err;

    key.src_ip = src_ip;
    key.dst_ip = dst_ip;
    key.src_port = src_port;
    key.dst_port = dst_port;
    key.proto = proto;

    /* 复制MAC地址 */
    memcpy(entry.dst_mac, mac, ETH_ALEN);
    entry.dst_ip = new_dst_ip;
    entry.action = action;

    err = bpf_map_update_elem(map_fd, &key, &entry, BPF_ANY);
    if (err) {
        fprintf(stderr, "Error: Failed to add flow rule: %s\n", strerror(errno));
        return -1;
    }

    printf("[+] Flow rule added: %pI4:%d -> %pI4:%d (proto=%d)\n",
           &src_ip, ntohs(src_port), &dst_ip, ntohs(dst_port), proto);
    return 0;
}

/* 删除转发规则 */
static int del_flow_rule(__u32 src_ip, __u32 dst_ip,
                         __u16 src_port, __u16 dst_port, __u8 proto)
{
    struct flow_key key = {0};
    int err;

    key.src_ip = src_ip;
    key.dst_ip = dst_ip;
    key.src_port = src_port;
    key.dst_port = dst_port;
    key.proto = proto;

    err = bpf_map_delete_elem(map_fd, &key);
    if (err) {
        fprintf(stderr, "Error: Failed to delete flow rule: %s\n", strerror(errno));
        return -1;
    }

    printf("[+] Flow rule deleted\n");
    return 0;
}

/* 显示统计信息 */
static void show_stats(void)
{
    struct stats s = {0};
    __u32 key = 0;
    int err;

    err = bpf_map_lookup_elem(stats_fd, &key, &s);
    if (err) {
        fprintf(stderr, "Error: Failed to lookup stats\n");
        return;
    }

    printf("\n========== XDP Statistics ==========\n");
    printf("RX Packets:    %llu\n", s.rx_packets);
    printf("TX Packets:    %llu\n", s.tx_packets);
    printf("Dropped:       %llu\n", s.dropped);
    printf("Parse Errors:  %llu\n", s.parse_err);
    printf("=====================================\n\n");
}

/* 显示所有流表项 */
static void show_flow_table(void)
{
    struct flow_key key;
    struct flow_key prev_key;
    struct forward_entry entry;
    __u32 prev = 0;
    int count = 0;

    printf("\n========== Flow Table ==========\n");

    while (bpf_map_get_next_key(map_fd, &prev, &key) == 0) {
        if (bpf_map_lookup_elem(map_fd, &key, &entry) == 0) {
            printf("[%d] %pI4:%d -> %pI4:%d (proto=%d) -> MAC:%pM, action=%d\n",
                   ++count, &key.src_ip, ntohs(key.src_port),
                   &key.dst_ip, ntohs(key.dst_port), key.proto,
                   entry.dst_mac, entry.action);
        }
        memcpy(&prev_key, &key, sizeof(prev_key));
    }

    if (count == 0) {
        printf("No flow entries\n");
    }
    printf("=================================\n\n");
}

/* 初始化默认转发规则 */
static int init_default_rules(void)
{
    /* 示例：添加一条默认规则 - 转发到本地 */
    __u8 mac[ETH_ALEN] = {0x00, 0x0c, 0x29, 0xab, 0xcd, 0xef};

    /* 10.0.0.1:8080 -> 10.0.0.2:80 (TCP) */
    __u32 src_ip = 0x0100000a;  /* 10.0.0.1 */
    __u32 dst_ip = 0x0200000a;  /* 10.0.0.2 */
    __u16 src_port = htons(8080);
    __u16 dst_port = htons(80);

    return add_flow_rule(src_ip, dst_ip, src_port, dst_port,
                         IPPROTO_TCP, mac, dst_ip, XDP_ACTION_TX);
}

/* 使用说明 */
static void usage(const char *prog)
{
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("Options:\n");
    printf("  -i <ifname>   Network interface to attach XDP (default: eth0)\n");
    printf("  -r            Run in daemon mode\n");
    printf("  -s            Show statistics\n");
    printf("  -f            Show flow table\n");
    printf("  -a            Add default flow rule\n");
    printf("  -d            Delete default flow rule\n");
    printf("  -h            Show this help\n");
}

int main(int argc, char **argv)
{
    int opt;
    int daemon_mode = 0;
    int show_stats_flag = 0;
    int show_flow_flag = 0;
    int add_rule_flag = 0;
    int del_rule_flag = 0;
    char *ifname = IFACE_NAME;

    /* 解析命令行参数 */
    while ((opt = getopt(argc, argv, "i:rsfadh")) != -1) {
        switch (opt) {
        case 'i':
            ifname = optarg;
            break;
        case 'r':
            daemon_mode = 1;
            break;
        case 's':
            show_stats_flag = 1;
            break;
        case 'f':
            show_flow_flag = 1;
            break;
        case 'a':
            add_rule_flag = 1;
            break;
        case 'd':
            del_rule_flag = 1;
            break;
        case 'h':
            usage(argv[0]);
            return 0;
        default:
            usage(argv[0]);
            return 1;
        }
    }

    /* 设置信号处理 */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    /* 加载 XDP 程序 */
    if (load_xdp_program(BPF_OBJ_FILE) < 0) {
        return 1;
    }

    /* 如果只显示统计或流表，不需要附加 XDP */
    if (show_stats_flag) {
        show_stats();
        return 0;
    }

    if (show_flow_flag) {
        show_flow_table();
        return 0;
    }

    /* 附加 XDP 到网卡 */
    if (attach_xdp(ifname) < 0) {
        return 1;
    }

    /* 添加默认规则 */
    if (add_rule_flag) {
        init_default_rules();
    }

    /* 删除默认规则 */
    if (del_rule_flag) {
        __u32 src_ip = 0x0100000a;
        __u32 dst_ip = 0x0200000a;
        __u16 src_port = htons(8080);
        __u16 dst_port = htons(80);
        del_flow_rule(src_ip, dst_ip, src_port, dst_port, IPPROTO_TCP);
    }

    /* 如果是守护进程模式 */
    if (daemon_mode) {
        if (daemon(0, 0) < 0) {
            fprintf(stderr, "Error: Failed to daemonize: %s\n", strerror(errno));
            return 1;
        }
    }

    /* 主循环 - 定期显示统计 */
    while (running) {
        sleep(5);
        if (running && daemon_mode) {
            show_stats();
        }
    }

    /* 清理 */
    detach_xdp();
    if (xdp_prog) {
        xdp_program__close(xdp_prog);
    }
    printf("[*] XDP controller stopped\n");

    return 0;
}
