/* xdp_user.c - XDP 用户态控制面程序
 * 使用 libxdp API
 * 实现eBPF Map管理、统计查询
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
#include <bpf/libbpf.h>
#include <xdp/libxdp.h>
#include "common.h"

/* 禁用 libbpf 的日志输出 */
static void disable_libbpf_log(void)
{
    libbpf_set_print(NULL);
}

#define IFACE_NAME "eth0"
#define BPF_OBJ_FILE "xdp_kern.o"

/* 全局变量 */
static int ifindex = -1;
static int prog_fd = -1;
static int map_fd = -1;
static int stats_fd = -1;
static struct xdp_program *xdp_prog = NULL;
static struct bpf_object *bpf_obj = NULL;
static int skb_mode = 0;
static volatile int running = 1;

/* 信号处理 */
static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* 查找 map fd */
static int find_map_fd(struct bpf_object *obj, const char *mapname)
{
    struct bpf_map *map;
    int fd = -1;

    map = bpf_object__find_map_by_name(obj, mapname);
    if (!map) {
        fprintf(stderr, "Error: cannot find map by name: %s\n", mapname);
        return -1;
    }

    fd = bpf_map__fd(map);
    if (fd < 0) {
        fprintf(stderr, "Error: failed to get fd for map %s: %s\n",
                mapname, strerror(errno));
        return -1;
    }

    return fd;
}

/* 加载 XDP 程序 - 使用 libxdp API */
static int load_xdp_program(const char *filename)
{
    int err;

    /* 使用 libxdp 打开并加载 XDP 程序 */
    xdp_prog = xdp_program__open_file(filename, "xdp", NULL);
    if (!xdp_prog) {
        fprintf(stderr, "Error: Failed to open XDP program: %s (errno=%d)\n",
                strerror(errno), errno);
        return -1;
    }

    /* 检查 libxdp 错误 */
    err = libxdp_get_error(xdp_prog);
    if (err) {
        char buf[256];
        libxdp_strerror(err, buf, sizeof(buf));
        fprintf(stderr, "Error: libxdp error: %s (err=%d)\n", buf, err);
        xdp_program__close(xdp_prog);
        xdp_prog = NULL;
        return -1;
    }

    printf("[+] XDP program opened\n");

    /* 获取 bpf_object */
    bpf_obj = xdp_program__bpf_obj(xdp_prog);
    if (!bpf_obj) {
        fprintf(stderr, "Error: Failed to get bpf_object\n");
        xdp_program__close(xdp_prog);
        xdp_prog = NULL;
        return -1;
    }

    printf("[+] Got bpf_object\n");
    return 0;
}

/* 分离已存在的 XDP 程序 */
static int detach_existing_xdp(const char *ifname)
{
    struct xdp_multiprog *mp;
    int ifindex;

    ifindex = if_nametoindex(ifname);
    if (!ifindex)
        return -1;

    /* 获取当前附加的 XDP 程序 */
    mp = xdp_multiprog__get_from_ifindex(ifindex);
    if (!mp) {
        /* 没有已存在的程序，这是正常的 */
        return 0;
    }

    /* 检查是否有错误 */
    if (libxdp_get_error(mp)) {
        xdp_multiprog__close(mp);
        return 0;
    }

    /* 分离已存在的程序 */
    printf("[*] Detaching existing XDP program from %s\n", ifname);
    xdp_multiprog__detach(mp);
    xdp_multiprog__close(mp);

    return 0;
}

/* 附加 XDP 到网卡 */
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

    /* 先分离已存在的 XDP 程序 */
    detach_existing_xdp(ifname);

    /* 短暂等待以确保分离完成 */
    usleep(100000);  // 100ms

    /* 使用 libxdp 附加程序 */
    /* 默认尝试 Native 模式，不行则切换到 SKB 模式 */
    int attach_mode = skb_mode ? XDP_MODE_SKB : XDP_MODE_NATIVE;
    err = xdp_program__attach(xdp_prog, ifindex, attach_mode, 0);
    if (err < 0 && !skb_mode) {
        /* Native 失败，尝试 SKB 模式 */
        fprintf(stderr, "libxdp: Error attaching XDP program in native mode: %s\n", strerror(-err));
        fprintf(stderr, "libxdp: Trying SKB mode instead...\n");
        err = xdp_program__attach(xdp_prog, ifindex, XDP_MODE_SKB, 0);
        if (err < 0) {
            fprintf(stderr, "Error: Failed to attach XDP to %s: %s (err=%d)\n",
                    ifname, strerror(-err), err);
            return -1;
        }
        printf("[+] XDP attached to %s (SKB mode - fallback)\n", ifname);
    } else if (err < 0) {
        fprintf(stderr, "Error: Failed to attach XDP to %s: %s (err=%d)\n",
                ifname, strerror(-err), err);
        return -1;
    } else {
        printf("[+] XDP attached to %s (Native mode)\n", ifname);
    }

    /* 获取程序 fd - 在 attach 之后才能获取 */
    prog_fd = xdp_program__fd(xdp_prog);
    if (prog_fd < 0) {
        fprintf(stderr, "Error: Failed to get program fd: %s (errno=%d)\n",
                strerror(errno), errno);
        return -1;
    }

    /* 获取 map fd - 在 attach 之后才能获取 */
    map_fd = find_map_fd(bpf_obj, "flow_table");
    if (map_fd < 0) {
        return -1;
    }

    stats_fd = find_map_fd(bpf_obj, "stats_map");
    if (stats_fd < 0) {
        return -1;
    }

    printf("[+] Got program fd: %d, map_fd: %d, stats_fd: %d\n",
           prog_fd, map_fd, stats_fd);

    return 0;
}

/* 分离 XDP */
static void detach_xdp(void)
{
    if (xdp_prog && ifindex > 0) {
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

    if (map_fd < 0) {
        fprintf(stderr, "Error: Map not initialized\n");
        return -1;
    }

    key.src_ip = src_ip;
    key.dst_ip = dst_ip;
    key.src_port = src_port;
    key.dst_port = dst_port;
    key.proto = proto;

    memcpy(entry.dst_mac, mac, ETH_ALEN);
    entry.dst_ip = new_dst_ip;
    entry.action = action;

    if (bpf_map_update_elem(map_fd, &key, &entry, BPF_ANY) < 0) {
        fprintf(stderr, "Error: Failed to add flow rule: %s\n", strerror(errno));
        return -1;
    }

    printf("[+] Added flow rule: %u.%u.%u.%u -> %u.%u.%u.%u\n",
           (src_ip >> 0) & 0xFF, (src_ip >> 8) & 0xFF,
           (src_ip >> 16) & 0xFF, (src_ip >> 24) & 0xFF,
           (new_dst_ip >> 0) & 0xFF, (new_dst_ip >> 8) & 0xFF,
           (new_dst_ip >> 16) & 0xFF, (new_dst_ip >> 24) & 0xFF);

    return 0;
}

/* 显示统计信息 */
static void show_stats(void)
{
    struct stats *s;
    __u32 key = 0;

    if (stats_fd < 0) {
        fprintf(stderr, "Error: Stats map not initialized\n");
        return;
    }

    s = malloc(sizeof(*s));
    if (!s) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        return;
    }

    if (bpf_map_lookup_elem(stats_fd, &key, s) < 0) {
        fprintf(stderr, "Error: Failed to lookup stats: %s\n", strerror(errno));
        free(s);
        return;
    }

    printf("=== XDP Statistics ===\n");
    printf("RX Packets: %llu\n", (unsigned long long)s->rx_packets);
    printf("TX Packets: %llu\n", (unsigned long long)s->tx_packets);
    printf("Dropped:    %llu\n", (unsigned long long)s->dropped);

    free(s);
}

/* 清理资源 */
static void cleanup(void)
{
    detach_xdp();
    if (xdp_prog) {
        xdp_program__close(xdp_prog);
        xdp_prog = NULL;
    }
}

/* 显示帮助 */
static void show_help(const char *prog)
{
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("Options:\n");
    printf("  -i <ifname>   Network interface to attach XDP (default: %s)\n", IFACE_NAME);
    printf("  -S            Use SKB (generic) mode\n");
    printf("  -r            Run in daemon mode\n");
    printf("  -s            Show statistics\n");
    printf("  -f            Show flow table\n");
    printf("  -a            Add default flow rule\n");
    printf("  -d            Delete default flow rule\n");
    printf("  -h            Show this help\n");
}

int main(int argc, char *argv[])
{
    int opt;
    const char *ifname = IFACE_NAME;

    /* 禁用 libbpf 的调试输出 */
    disable_libbpf_log();
    int daemon_mode = 0;
    int show_stats_flag = 0;
    int add_rule = 0;

    while ((opt = getopt(argc, argv, "i:Srsfadh")) != -1) {
        switch (opt) {
            case 'i':
                ifname = optarg;
                break;
            case 'S':
                skb_mode = 1;
                break;
            case 'r':
                daemon_mode = 1;
                break;
            case 's':
                show_stats_flag = 1;
                break;
            case 'a':
                add_rule = 1;
                break;
            case 'h':
                show_help(argv[0]);
                return 0;
            default:
                show_help(argv[0]);
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

    /* 附加到网络接口 */
    if (attach_xdp(ifname) < 0) {
        cleanup();
        return 1;
    }

    /* 添加默认转发规则 */
    if (add_rule) {
        // 测试环境：192.168.88.10 -> 192.168.88.20
        __u8 default_mac[ETH_ALEN] = {0x56, 0xa6, 0x09, 0xd7, 0xd0, 0x10};  // veth1 MAC
        __u32 dst_ip = inet_addr("192.168.88.20");  // veth1 IP

        // 转发所有 TCP 流量
        add_flow_rule(inet_addr("0.0.0.0"), inet_addr("192.168.88.10"),
                      0, 80, IPPROTO_TCP, default_mac, dst_ip, XDP_ACTION_TX);
    }

    /* 显示统计信息 */
    if (show_stats_flag) {
        show_stats();
    }

    /* 守护进程模式 */
    if (daemon_mode) {
        printf("[*] Running in daemon mode, press Ctrl+C to stop\n");
        while (running) {
            sleep(1);
        }
    } else {
        printf("[*] XDP controller running, press Ctrl+C to stop\n");
        while (running) {
            sleep(1);
        }
    }

    /* 清理 */
    cleanup();
    printf("[*] XDP controller stopped\n");

    return 0;
}
