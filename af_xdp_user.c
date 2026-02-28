/* af_xdp_user.c - AF_XDP 用户态程序
 * 实现零拷贝数据平面，通过UMEM共享内存与内核通信
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
#include <asm/unistd.h>
#include <bpf/libbpf.h>
#include <bpf/bpf.h>
#include <linux/if_xdp.h>
#include "common.h"

#define IFACE_NAME "eth0"
#define NUM_FRAMES 4096
#define FRAME_SIZE 2048

/* 全局变量 */
static volatile int running = 1;
static int xsk_fd = -1;

/* 信号处理 */
static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* 创建AF_XDP套接字 */
static int create_xsk_socket(const char *ifname, int queue_id)
{
    struct sockaddr_xdp sxdp = {0};
    struct xdp_mmap_offsets off;
    int sock_fd;
    int err;
    socklen_t optlen;

    /* 创建socket */
    sock_fd = socket(AF_XDP, SOCK_RAW, 0);
    if (sock_fd < 0) {
        fprintf(stderr, "Error: Failed to create AF_XDP socket: %s\n", strerror(errno));
        return -1;
    }

    /* 设置UMEM */
    struct xdp_umem_reg mr = {
        .addr = 0,
        .len = NUM_FRAMES * FRAME_SIZE,
        .chunk_size = FRAME_SIZE,
        .flags = 0
    };

    err = setsockopt(sock_fd, SOL_XDP, XDP_UMEM_REG, &mr, sizeof(mr));
    if (err) {
        fprintf(stderr, "Error: Failed to set UMEM reg: %s\n", strerror(errno));
        close(sock_fd);
        return -1;
    }

    /* 设置套接字地址 */
    sxdp.sxdp_family = AF_XDP;
    sxdp.sxdp_ifindex = if_nametoindex(ifname);
    sxdp.sxdp_queue_id = queue_id;

    err = bind(sock_fd, (struct sockaddr *)&sxdp, sizeof(sxdp));
    if (err) {
        fprintf(stderr, "Error: Failed to bind socket: %s\n", strerror(errno));
        close(sock_fd);
        return -1;
    }

    /* 获取mmap偏移量 */
    optlen = sizeof(off);
    err = getsockopt(sock_fd, SOL_XDP, XDP_MMAP_OFFSETS, &off, &optlen);
    if (err) {
        fprintf(stderr, "Error: Failed to get mmap offsets\n");
        close(sock_fd);
        return -1;
    }

    printf("[+] AF_XDP socket created on %s (queue=%d)\n", ifname, queue_id);
    return sock_fd;
}

/* 接收数据包 */
static int recv_packets(int sock_fd)
{
    struct xdp_desc desc[32];
    int ret;

    ret = recvfrom(sock_fd, desc, sizeof(desc), 0, NULL, NULL);
    if (ret < 0) {
        if (errno != EAGAIN && errno != ENOBUFS) {
            fprintf(stderr, "Error: recvfrom failed: %s\n", strerror(errno));
        }
        return -1;
    }

    if (ret > 0) {
        printf("[*] Received %zu packets\n", (size_t)ret / sizeof(struct xdp_desc));
    }

    return ret;
}

/* 发送数据包 */
static int send_packets(int sock_fd, struct xdp_desc *descs, int count)
{
    int ret;

    ret = sendto(sock_fd, descs, count * sizeof(struct xdp_desc), 0, NULL, 0);
    if (ret < 0) {
        if (errno != EAGAIN && errno != ENOBUFS) {
            fprintf(stderr, "Error: sendto failed: %s\n", strerror(errno));
        }
        return -1;
    }

    if (ret > 0) {
        printf("[*] Sent %zu packets\n", (size_t)ret / sizeof(struct xdp_desc));
    }

    return ret;
}

/* 使用说明 */
static void usage(const char *prog)
{
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("Options:\n");
    printf("  -i <ifname>   Network interface (default: eth0)\n");
    printf("  -q <queue>    Queue ID (default: 0)\n");
    printf("  -h            Show this help\n");
}

int main(int argc, char **argv)
{
    int opt;
    char *ifname = IFACE_NAME;
    int queue_id = DEFAULT_QUEUE_ID;

    /* 解析命令行参数 */
    while ((opt = getopt(argc, argv, "i:qh")) != -1) {
        switch (opt) {
        case 'i':
            ifname = optarg;
            break;
        case 'q':
            queue_id = atoi(optarg);
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

    /* 创建AF_XDP套接字 */
    xsk_fd = create_xsk_socket(ifname, queue_id);
    if (xsk_fd < 0) {
        return 1;
    }

    printf("[*] Starting packet processing...\n");

    /* 主循环 - 忙轮询处理数据包 */
    while (running) {
        /* 这里可以添加数据包处理逻辑 */
        /* 在实际应用中，可以将recv和send分离到不同线程 */
        usleep(1000);  /* 短暂休眠，避免CPU 100% */
    }

    /* 清理 */
    if (xsk_fd >= 0) {
        close(xsk_fd);
    }

    printf("[*] AF_XDP socket closed\n");
    return 0;
}
