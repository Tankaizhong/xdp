# XDP Cluster Forwarding Project

基于eBPF/XDP的高性能集群网络转发系统，实现微秒级延迟和千万级PPS吞吐量。

## 特性

- **XDP (Express Data Path)**: 在网卡驱动层直接处理数据包，绕过内核协议栈
- **AF_XDP**: 用户态零拷贝通信，通过UMEM共享内存
- **O(1)查表**: 使用BPF_HASH_MAP实现高速转发
- **五元组匹配**: 支持IP/TCP/UDP协议解析
- **灵活转发**: 支持XDP_TX、XDP_REDIRECT等多种模式
- **统计监控**: 实时流量统计和性能监控

## 系统架构

```
+------------------+     +-------------------+
|   Application   |     |   Application     |
|   (Server A)     |<--->|   (Server B)      |
+--------+---------+     +---------+---------+
         |                       ^
         |                       |
+--------v---------+     +--------+---------+
|   AF_XDP User   |     |   AF_XDP User    |
|   Space         |     |   Space           |
+--------+---------+     +--------+---------+
         |                       ^
         |                       |
+--------v----------------------+---------+
|           XDP eBPF Kernel               |
|  - Five-tuple extraction                |
|  - O(1) flow lookup                     |
|  - XDP_TX / XDP_REDIRECT               |
+--------+---------+     +--------+--------+
         |                       ^
         |                       |
+--------v---------+     +--------+--------+
|  Physical NIC    |     |  Physical NIC   |
|  (eth0)          |     |  (eth1)          |
+------------------+     +------------------+
```

## 环境要求

- Linux Kernel 4.18+
- clang 编译器
- llvm
- libbpf-dev
- pkg-config
- root 权限（加载XDP程序）

### 安装依赖 (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y clang llvm make gcc libbpf-dev pkg-config linux-headers-$(uname -r)
```

### 安装依赖 (CentOS/RHEL)

```bash
sudo yum install -y clang llvm make gcc pkgconfig
sudo yum install -y libbpf-devel kernel-headers
```

## 快速开始

### 1. 编译

```bash
make clean
make all
```

### 2. 部署

```bash
# 完整部署（需要root）
sudo ./deploy.sh deploy

# 或分步执行
sudo ./deploy.sh build      # 编译程序
sudo ./deploy.sh load       # 加载XDP到网卡
sudo ./deploy.sh start       # 启动控制器
```

### 3. 测试

```bash
# 运行所有测试
./test.sh all

# 单独测试
./test.sh loaded   # 检查XDP是否加载
./test.sh stats    # 查看统计信息
./test.sh flow     # 查看流表
./test.sh throughput  # 吞吐量测试
./test.sh latency  # 延迟测试
```

## 项目文件说明

| 文件 | 说明 |
|------|------|
| `common.h` | 共享头文件，定义eBPF Map和数据结构 |
| `xdp_kern.c` | XDP eBPF内核程序（BPF） |
| `xdp_user.c` | XDP用户态控制面程序 |
| `af_xdp_user.c` | AF_XDP用户态程序（零拷贝） |
| `Makefile` | 构建系统 |
| `deploy.sh` | 集群部署脚本 |
| `test.sh` | 测试验证脚本 |

## 使用说明

### XDP控制器

```bash
# 添加转发规则
sudo ./xdp_controller -a

# 查看统计信息
./xdp_controller -s

# 查看流表
./xdp_controller -f

# 指定网卡启动（守护模式）
sudo ./xdp_controller -i eth0 -r

# 查看帮助
./xdp_controller -h
```

### AF_XDP转发器

```bash
# 启动AF_XDP转发
sudo ./af_xdp_forwarder -i eth0 -q 0
```

### 部署脚本

```bash
./deploy.sh help

# 可用命令
./deploy.sh deploy    # 完整部署
./deploy.sh build     # 编译
./deploy.sh load      # 加载XDP
./deploy.sh start     # 启动
./deploy.sh stop      # 停止
./deploy.sh verify    # 验证
./deploy.sh uninstall # 卸载
```

### 测试脚本

```bash
./test.sh help

# 可用测试
./test.sh all           # 所有测试
./test.sh loaded        # 检查加载
./test.sh stats         # 统计信息
./test.sh flow          # 流表
./test.sh throughput    # 吞吐量
./test.sh latency       # 延迟
```

## 配置选项

### 环境变量

```bash
# 指定网卡接口
export IFACE=eth0

# 指定测试时长
export TEST_DURATION=30
```

### 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-i` | 网卡名称 | eth0 |
| `-q` | 队列ID | 0 |
| `-r` | 守护模式 | false |
| `-s` | 显示统计 | false |
| `-f` | 显示流表 | false |
| `-a` | 添加规则 | false |
| `-d` | 删除规则 | false |

## 性能优化

### 1. 使用Native模式

优先使用驱动层XDP（native mode），性能比generic模式高10倍：

```bash
# 自动检测并使用最佳模式
ip link set eth0 xdp obj xdp_kern.o sec xdp
```

### 2. 配置HugePages

```bash
# 配置大页内存（AF_XDP需要）
echo 128 > /proc/sys/vm/nr_hugepages
```

### 3. CPU亲和性

将XDP处理线程绑定到特定CPU核心：

```bash
# 查看可用核心
nproc

# 绑定进程到核心0
taskset -c 0 ./xdp_controller
```

### 4. 关闭不必要的功能

```bash
# 关闭rp_filter
sysctl -w net.ipv4.conf.all.rp_filter=0

# 增大ring buffer
sysctl -w net.core.rmem_max=8388608
```

## 预期性能

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 吞吐量 | ≥2000万 PPS | 单机处理能力 |
| 时延 | ≤10μs | 微秒级延迟 |
| CPU开销 | 降低75% | 相比传统方案 |

## 故障排除

### XDP加载失败

```bash
# 检查网卡是否支持
ethtool -k eth0 | grep xdp

# 查看内核日志
dmesg | tail -50

# 尝试generic模式
ip link set eth0 xdp obj xdp_kern.o sec xdp mode generic
```

### 编译错误

```bash
# 检查clang版本
clang --version

# 检查libbpf
pkg-config --modversion libbpf
```

### 性能问题

```bash
# 检查XDP模式（应为native）
ip link show eth0

# 检查统计
./xdp_controller -s

# 检查丢包
./test.sh dropped
```

## 集群部署示例

### 节点1 (Ingress)

```bash
sudo ./deploy.sh deploy
sudo ./xdp_controller -i eth0 -r
```

### 节点2 (Egress)

```bash
sudo ./deploy.sh deploy
# 配置相应的转发规则
```

## 扩展开发

### 添加新的转发策略

修改 `xdp_kern.c` 中的 `flow_lookup` 函数：

```c
static __always_inline struct forward_entry* flow_lookup(...)
{
    // 添加自定义匹配逻辑
}
```

### 添加新的协议支持

在 `common.h` 中添加协议定义，并在 `xdp_kern.c` 中添加解析逻辑。

## 许可证

GPL v2

## 参考资料

- [XDP官方文档](https://www.kernel.org/doc/html/latest/networking/af_xdp.html)
- [libbpf库](https://github.com/libbpf/libbpf)
- [BPF Performance Tools](https://www.brendangregg.com/bpf-performance-tools-book.html)
