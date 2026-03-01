# XDP 集群转发项目

基于 eBPF/XDP 的高性能集群转发系统。

## 为什么选择 XDP？

XDP（Express Data Path）是 Linux 内核的一项特性，允许在网络栈的最早阶段对数据包进行可编程处理——在内核主网络栈处理数据包之前。这为数据包转发提供了接近原生性能的处理能力。

### 核心特性

- **内核旁路** - 在内核网络栈之前处理数据包
- **零拷贝转发** - 使用 AF_XDP 直接 DMA 到用户空间
- **基于流的分发** - 使用类似 RSS 的哈希进行负载均衡
- **内核加速** - 使用 eBPF map 实现快速查找

### 应用场景

- 负载均衡器（L4/L7）
- DDoS 防护
- 防火墙
- 网络流量分析
- Service Mesh Sidecar

## 网络拓扑

![网络拓扑图](./example.png)

### 组件说明

| 组件 | 说明 |
|------|------|
| **eth0** | 接收外部流量的前端网络接口 |
| **XDP 程序 (xdp_kern.o)** | 加载到内核的 eBPF 程序，在网卡层面处理数据包 |
| **流表** | 存储活动连接和后端选择的 eBPF map |
| **后端服务器** | 处理请求的真实后端服务 |

## 工作原理

### 数据包处理流程

```
┌─────────────────┐
│   数据包到达     │
│   网卡接收      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  XDP 钩子点     │  ← 首次处理数据包的机会
│  (驱动层)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  解析数据包     │  ← 提取头部（以太网、IP、TCP/UDP）
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  流表查找       │  ← 检查连接是否存在于流表中
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌───────┐
│ 新建  │ │ 已知  │
│ 连接  │ │ 连接  │
└───┬───┘ └───┬───┘
    │         │
    ▼         ▼
┌───────────┐ ┌───────────┐
│ 选择      │ │ 从 Map   │
│ 后端      │ │ 获取后端  │
│ (RR/哈希) │ │           │
└───┬───────┘ └─────┬─────┘
    │               │
    └───────┬───────┘
            │
            ▼
┌─────────────────┐
│  重定向到后端   │  ← 通过 XDP_TX 或 devmap 发送
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  更新统计       │  ← 记录数据包/字节计数
└─────────────────┘
```

### 步骤详解

1. **数据包到达**
   - 网卡接收数据包
   - XDP 程序首先访问数据包

2. **头部解析**
   - 解析以太网头部 → 获取协议类型
   - 解析 IP 头部 → 获取源/目标 IP
   - 解析 TCP/UDP 头部 → 获取源/目标端口
   - 提取 5 元组：(协议, 源IP, 目标IP, 源端口, 目标端口)

3. **流表查找**
   - 使用 5 元组哈希在 eBPF map 中查找
   - 找到 → 使用现有后端
   - 未找到 → 使用轮询或哈希选择新后端

4. **后端选择**
   - 轮询：均匀分配到各个后端
   - 源哈希：确保同一客户端访问同一后端
   - 最少连接：跟踪每个后端的活动连接数

5. **数据包重定向**
   - 使用 XDP 重定向发送数据包到后端
   - 可以重定向到：
     - 另一个接口（XDP_TX）
     - BPF devmap（虚拟接口）
     - AF_XDP socket（用户空间）

6. **统计更新**
   - 增加数据包计数
   - 更新字节计数
   - 更新连接跟踪

## 项目结构

```
xdp/
├── lib/
│   ├── common/       # 公共库
│   ├── libbpf/       # libbpf 静态库
│   ├── libxdp/       # libxdp 静态库
│   └── xdp-tools/    # xdp-tools（子模块）
├── xdp_kern.c        # XDP 内核程序（在内核中运行）
├── xdp_user.c        # XDP 控制器（用户空间）
├── af_xdp_user.c     # AF_XDP 转发器（零拷贝模式）
├── common.h          # 公共定义头文件
├── deploy.sh         # 部署脚本
├── test.sh           # 测试脚本
└── Makefile          # 构建文件
```

### 关键文件

| 文件 | 说明 |
|------|------|
| `xdp_kern.c` | 在内核中运行的 eBPF 程序 - 处理数据包 |
| `xdp_user.c` | 用户空间控制器 - 管理 XDP 程序和流表 |
| `af_xdp_user.c` | AF_XDP 实现 - 零拷贝转发到用户空间 |
| `common.h` | 内核和用户空间共享的头文件 |
| `deploy.sh` | 一键部署脚本 |

## 编译

```bash
# 安装依赖
sudo apt-get install build-essential clang llvm libelf-dev iproute2 git

# 克隆并编译
git clone https://github.com/Tankaizhong/xdp.git
cd xdp
git submodule update --init --recursive
make
```

## 使用

### 快速开始

```bash
# 部署 XDP 程序
sudo ./deploy.sh deploy

# 或者分步执行
sudo ./deploy.sh build    # 编译程序
sudo ./deploy.sh load     # 加载 XDP 到接口
sudo ./deploy.sh start    # 启动控制器
```

### 手动控制

```bash
# 编译 XDP 程序
make

# 加载 XDP 到接口（将 eth0 替换为你的接口）
sudo ip link set eth0 xdp obj xdp_kern.o sec xdp

# 查看 XDP 状态
ip link show eth0

# 启动控制器（显示统计信息）
sudo ./xdp_user -s

# 启动控制器（显示流表）
sudo ./xdp_user -f

# 启动控制器（AF_XDP 模式）
sudo ./af_xdp_user -s
```

### 测试

```bash
# 运行测试套件
sudo ./test.sh all

# 单独测试
sudo ./test.sh loaded   # 检查 XDP 是否加载
sudo ./test.sh stats    # 查看 XDP 统计
sudo ./test.sh mode     # 检查 XDP 模式
sudo ./test.sh latency  # 延迟测试
```

## 配置

### 添加后端服务器

编辑 `xdp_user.c` 修改 `backends` 数组：

```c
static struct backend backends[] = {
    { .ip = "192.168.1.10", .port = 8080 },
    { .ip = "192.168.1.11", .port = 8080 },
    { .ip = "192.168.1.12", .port = 8080 },
};
```

### 修改负载均衡算法

在 `xdp_kern.c` 中修改 `select_backend` 函数：

```c
// 轮询（默认）
backend_id = round_robin_index % num_backends;

// 源哈希（一致性哈希）
backend_id = src_hash % num_backends;

// 随机
backend_id = bpf_get_prandom_u32() % num_backends;
```

## 监控

### 查看统计信息

```bash
# 使用 xdp_user
sudo ./xdp_user -s

# 使用 ip 命令
ip -s link show eth0
```

### 查看流表

```bash
# 显示当前连接
sudo ./xdp_user -f
```

### 调试 XDP

```bash
# 查看 XDP 日志
sudo cat /sys/kernel/debug/tracing/trace_pipe

# 设置调试缓冲区
sudo mount -t tracefs tracefs /sys/kernel/debug/tracing
```

## 环境要求

- Linux 内核 5.4+ 并支持 XDP
- clang 和 llvm
- libelf-dev
- iproute2

### 检查 XDP 支持

```bash
# 检查内核是否支持 XDP
ip link set eth0 xdp off
```

## 性能调优

1. **大页内存**
   ```bash
   sudo sysctl -w vm.nr_hugepages=1024
   ```

2. **锁定内存**
   ```bash
   sudo ulimit -l unlimited
   ```

3. **CPU 亲和性**
   ```bash
   sudo taskset -c 0 ./xdp_user
   ```

## 许可证

GPL-2.0

## 参考资料

- [XDP 官方文档](https://www.kernel.org/doc/Documentation/networking/filter.txt)
- [libbpf GitHub](https://github.com/libbpf/libbpf)
- [xdp-tools GitHub](https://github.com/xdp-project/xdp-tools)
- [BPF Performance Tools](http://www.brendangregg.com/bpfperformance.html)
