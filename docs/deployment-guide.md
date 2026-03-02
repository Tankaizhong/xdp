# XDP 负载均衡器物理机部署指南

本文档详细介绍如何在物理服务器上部署 XDP 负载均衡器。

## 目录

- [前置要求](#前置要求)
- [网络拓扑](#网络拓扑)
- [服务器角色](#服务器角色)
- [网络配置](#网络配置)
- [编译部署](#编译部署)
- [验证测试](#验证测试)
- [故障排查](#故障排查)
- [维护操作](#维护操作)

---

## 前置要求

### 硬件要求

| 角色 | CPU | 内存 | 网卡 |
|------|-----|------|------|
| Load Balancer | 2+ 核心 | 2GB+ | 2 张网卡 |
| Backend Server | 1+ 核心 | 1GB+ | 1 张网卡 |

### 软件要求

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    clang \
    llvm \
    libelf-dev \
    libbpf-dev \
    libxdp-dev \
    pkg-config \
    iproute2 \
    git \
    netcat-openbsd

# 检查内核版本 (需要 5.4+)
uname -r
```

### 内核要求

- Linux 内核 5.4 或更高版本
- 支持 XDP 的网卡驱动

检查网卡是否支持 XDP：
```bash
# 尝试加载 XDP，如果网卡不支持会报错
ip link set eth0 xdp off
```

---

## 网络拓扑

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   客户端    │         │  XDP LB    │         │   后端 1    │
│             │         │             │         │             │
│  任意 IP   │────eth0─▶│ 192.168.88.10│         │192.168.89.101│
│             │  VIP    │             │         │   :8080     │
└─────────────┘         └──────┬──────┘         └─────────────┘
                               │
                            eth1│(内网口 192.168.89.10)
                               │
                     ┌─────────┴─────────┐
                     │    交换机/集线器   │
                     └─────────┬─────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
┌─────────────────────┐           ┌─────────────────────┐
│       后端 1        │           │       后端 2        │
│                     │           │                     │
│  192.168.89.101    │           │  192.168.89.102    │
│      :8080          │           │      :8080          │
└─────────────────────┘           └─────────────────────┘
```

### IP 规划表

| 角色 | 接口 | IP 地址 | 说明 |
|------|------|---------|------|
| Load Balancer | eth0 (前端) | 192.168.88.10/24 | VIP，接收客户端流量 |
| Load Balancer | eth1 (后端) | 192.168.89.10/24 | 连接后端服务器 |
| Backend 1 | eth0 | 192.168.89.101/24 | 后端服务 #1 |
| Backend 2 | eth0 | 192.168.89.102/24 | 后端服务 #2 |
| 客户端 | 任意 | 任意 | 访问 VIP |

---

## 服务器角色

### 1. Load Balancer 服务器

这是核心节点，运行 XDP 程序进行负载均衡。

#### 1.1 网络配置

```bash
# 临时配置 (重启后失效)
sudo ip addr add 192.168.88.10/24 dev eth0
sudo ip addr add 192.168.89.10/24 dev eth1
sudo ip link set eth0 up
sudo ip link set eth1 up

# 永久配置 (Ubuntu/Debian)
# 编辑 /etc/netplan/01-netcfg.yaml
```

**永久配置示例** (`/etc/netplan/01-netcfg.yaml`)：

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - 192.168.88.10/24
      mtu: 9000
    eth1:
      addresses:
        - 192.168.89.10/24
      mtu: 9000
```

```bash
# 应用配置
sudo netplan apply

# 验证配置
ip addr show
```

#### 1.2 系统参数配置

```bash
# 启用 IP 转发
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-xdp.conf

# 禁用 rp_filter (XDP 转发场景)
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
echo "net.ipv4.conf.all.rp_filter=0" | sudo tee -a /etc/sysctl.d/99-xdp.conf

# 增大网络缓冲区
sudo sysctl -w net.core.rmem_max=8388608
sudo sysctl -w net.core.rmem_default=8388608
echo "net.core.rmem_max=8388608" | sudo tee -a /etc/sysctl.d/99-xdp.conf

# 配置大页内存 (AF_XDP 模式需要)
sudo sysctl -w vm.nr_hugepages=128
echo "vm.nr_hugepages=128" | sudo tee -a /etc/sysctl.d/99-xdp.conf
```

#### 1.3 克隆项目

```bash
# 克隆代码
git clone https://github.com/Tankaizhong/xdp.git
cd xdp

# 安装依赖
sudo apt install build-essential clang llvm libelf-dev libbpf-dev libxdp-dev zstd gcc-multilib pkg-config iproute2

# 检查环境依赖
./configure

# 编译
make
```

#### 1.4 部署 XDP

```bash
# 方式一: 一键部署 (推荐)
sudo ./scripts/deploy.sh deploy

# 方式二: 手动部署

# 1. 加载 XDP 程序到 eth0
sudo ip link set eth0 xdp obj xdp_kern.o sec xdp

# 2. 验证加载成功
ip link show eth0

# 3. 启动控制器 (前台模式，显示统计)
sudo ./xdp_user -i eth0 -s

# 4. 或者后台模式运行
sudo ./xdp_user -i eth0 -r
```

---

### 2. Backend 服务器 (2台)

每台后端服务器运行一个 HTTP 服务。

#### 2.1 网络配置

```bash
# Backend 1
sudo ip addr add 192.168.89.101/24 dev eth0
sudo ip link set eth0 up
sudo ip route add default via 192.168.89.10

# Backend 2
sudo ip addr add 192.168.89.102/24 dev eth0
sudo ip link set eth0 up
sudo ip route add default via 192.168.89.10
```

#### 2.2 启动 HTTP 服务

```bash
# 方式一: 使用 nc (简单测试)
# Backend 1
while true; do echo "Backend 1 - $(hostname)" | nc -l -p 8080; done &

# Backend 2
while true; do echo "Backend 2 - $(hostname)" | nc -l -p 8080; done &
```

```bash
# 方式二: 使用 Python
# Backend 1
python3 -m http.server 8080 --directory /tmp &

# 方式三: 使用 Docker
docker run -d -p 8080:80 --name nginx nginx:latest
```

---

### 3. 客户端测试

客户端可以是任意能发送 HTTP 请求的设备。

```bash
# 测试单个请求
curl http://192.168.88.10:8080

# 循环测试负载均衡
for i in {1..30}; do
    echo "Request $i: $(curl -s http://192.168.88.10:8080)"
done

# 或者使用 ab 进行压力测试
ab -n 1000 -c 10 http://192.168.88.10:8080 修改 IP 配置

### 修改后端服务器 IP

编辑 `src/
```

---

##/main/xdp_user.c`：

```c
// 找到后端配置，修改 IP 地址
static struct backend backends[] = {
    { .ip = "192.168.89.101", .port = 8080 },
    { .ip = "192.168.89.102", .port = 8080 },
};
```

重新编译部署：

```bash
make clean
make
sudo ip link set eth0 xdp off
sudo ip link set eth0 xdp obj xdp_kern.o sec xdp
sudo ./xdp_user -i eth0 -r
```

### 修改负载均衡算法

编辑 `bpf/xdp_kern.c`，找到 `select_backend` 函数：

```c
// 轮询 (默认)
backend_id = round_robin_index % num_backends;

// 源哈希 (同一客户端访问同一后端)
backend_id = src_hash % num_backends;

// 随机
backend_id = bpf_get_prandom_u32() % num_backends;
```

---

## 验证测试

### 1. 检查 XDP 状态

```bash
# 查看网卡 XDP 状态
ip link show eth0

# 应该看到类似输出:
# 2: eth0: <BROADCAST,MULTICAST,UP> mtu 9000 xdp id 100 prog/sec xdp
```

### 2. 查看统计信息

```bash
# 方式一: 使用 xdp_user
sudo ./xdp_user -i eth0 -s

# 方式二: 使用 ip 命令
ip -s link show eth0
```

### 3. 查看流表

```bash
sudo ./xdp_user -i eth0 -f
```

### 4. 查看内核日志

```bash
dmesg | tail -50
sudo cat /sys/kernel/debug/tracing/trace_pipe
```

---

## 故障排查

### 问题: XDP 加载失败

**症状**: `ip link set eth0 xdp obj xdp_kern.o sec xdp` 报错

**解决**:
```bash
# 检查内核支持
ip link set eth0 xdp off

# 使用 generic 模式 (兼容性好，但性能较低)
sudo ip link set eth0 xdp mode generic obj xdp_kern.o sec xdp
```

### 问题: 无法连接后端

**检查清单**:
```bash
# 1. 检查后端 IP 是否可达
ping 192.168.89.101

# 2. 检查后端服务是否运行
curl http://192.168.89.101:8080

# 3. 检查后端网卡状态
ip link show eth1

# 4. 检查防火墙
sudo iptables -L -n
```

### 问题: 负载不均衡

**原因**: 可能是使用了源哈希算法

**解决**:
```bash
# 检查当前算法，参考上面的"修改负载均衡算法"部分
```

### 问题: 性能不理想

**优化建议**:
1. 使用 native 模式而非 generic 模式
2. 配置大页内存
3. 锁定内存限制
4. CPU 亲和性绑定

```bash
# 锁定内存
sudo ulimit -l unlimited

# CPU 亲和性
sudo taskset -c 0,1 ./xdp_user -i eth0 -r
```

---

## 维护操作

### 停止 XDP 服务

```bash
# 停止控制器
sudo pkill -f xdp_user

# 卸载 XDP 程序
sudo ip link set eth0 xdp off
```

### 重启 XDP 服务

```bash
sudo ./scripts/deploy.sh stop
sudo ./scripts/deploy.sh deploy
```

### 更新代码后重新部署

```bash
# 拉取最新代码
git pull

# 重新编译
make clean
make

# 重新加载
sudo ip link set eth0 xdp off
sudo ip link set eth0 xdp obj xdp_kern.o sec xdp
sudo ./xdp_user -i eth0 -r
```

### 使用 systemd 管理

安装 systemd 服务：

```bash
sudo cp deployment/systemd/xdp-lb.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable xdp-lb
sudo systemctl start xdp-lb

# 查看状态
sudo systemctl status xdp-lb
```

---

## 使用 Docker 部署

如果不想直接在物理机上部署，可以使用 Docker：

```bash
# 构建镜像
docker build -t xdp-lb:latest .

# 运行
docker run -d --privileged \
    --name xdp-lb \
    -v /sys/fs/bpf:/sys/fs/bpf \
    -v /lib/modules:/lib/modules:ro \
    xdp-lb:latest

# 进入容器配置网络
docker exec -it xdp-lb bash
```

---

## 参考资料

- [XDP 官方文档](https://www.kernel.org/doc/Documentation/networking/filter.txt)
- [libbpf GitHub](https://github.com/libbpf/libbpf)
- [BPF Performance Tools](http://www.brendangregg.com/bpfperformance.html)
