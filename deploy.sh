#!/bin/bash
# deploy.sh - XDP 集群部署脚本
# 用于在集群节点上部署和配置 XDP 转发

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
IFACE="${IFACE:-eth0}"
BACKEND_IFACE="${BACKEND_IFACE:-eth1}"
XDP_CONTROLLER="./xdp_user"
AF_XDP_FORWARDER="./af_xdp_user"
BPF_OBJ="./xdp_kern.o"

# 自动获取本机IP
get_ip() {
    local iface=$1
    ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1
}

# 自动检测网络配置
detect_network_config() {
    log_info "Detecting network configuration..."

    # 获取前端接口IP (VIP)
    FRONTEND_IP=$(get_ip "$IFACE")
    if [[ -z "$FRONTEND_IP" ]]; then
        log_warn "No IP found on $IFACE, using default 192.168.88.10"
        FRONTEND_IP="192.168.88.10"
    else
        log_info "Frontend IP detected: $FRONTEND_IP"
    fi

    # 获取后端接口IP
    BACKEND_IP=$(get_ip "$BACKEND_IFACE")
    if [[ -z "$BACKEND_IP" ]]; then
        log_warn "No IP found on $BACKEND_IFACE, using default 192.168.89.10"
        BACKEND_IP="192.168.89.10"
    else
        log_info "Backend IP detected: $BACKEND_IP"
    fi

    # 从后端IP推导后端网段
    BACKEND_NETWORK=$(echo "$BACKEND_IP" | sed 's/\.[0-9]*$/.*/')
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    log_info "Checking dependencies..."

    local deps=("clang" "make" "gcc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Missing dependency: $dep"
            exit 1
        fi
    done

    # 检查libbpf
    if ! pkg-config --exists libbpf 2>/dev/null; then
        log_warn "libbpf-dev may not be installed"
    fi

    log_info "All dependencies satisfied"
}

# 检查内核支持
check_kernel_support() {
    log_info "Checking kernel XDP support..."

    # 检查网卡是否支持XDP
    if ! ip link show "$IFACE" &> /dev/null; then
        log_error "Interface $IFACE not found"
        exit 1
    fi

    # 检查是否已加载XDP
    if ip link show "$IFACE" | grep -q "xdp"; then
        log_warn "XDP already attached to $IFACE"
    fi

    log_info "Kernel XDP support verified"
}

# 编译程序
build_programs() {
    log_info "Building XDP programs..."

    if [[ ! -f "Makefile" ]]; then
        log_error "Makefile not found"
        exit 1
    fi

    make clean
    make all

    if [[ ! -f "$BPF_OBJ" ]] || [[ ! -f "$XDP_CONTROLLER" ]]; then
        log_error "Build failed"
        exit 1
    fi

    log_info "Build successful"
}

# 配置系统参数
configure_system() {
    log_info "Configuring system parameters..."

    # 增大ring buffer
    if [[ -f /proc/sys/net/core/rmem_max ]]; then
        echo 8388608 > /proc/sys/net/core/rmem_max
    fi

    if [[ -f /proc/sys/net/core/rmem_default ]]; then
        echo 8388608 > /proc/sys/net/core/rmem_default
    fi

    # 禁用rp_filter（对于转发场景）
    sysctl -w net.ipv4.conf.all.rp_filter=0 2>/dev/null || true
    sysctl -w net.ipv4.conf.default.rp_filter=0 2>/dev/null || true

    # 启用IP转发
    sysctl -w net.ipv4.ip_forward=1

    # 配置HugePages（用于AF_XDP）
    if [[ -f /proc/sys/vm/nr_hugepages ]]; then
        echo 128 > /proc/sys/vm/nr_hugepages
    fi

    log_info "System parameters configured"
}

# 配置CPU亲和性（可选）
configure_cpu_affinity() {
    log_info "Configuring CPU affinity..."

    # 获取可用CPU核心
    local num_cpus=$(nproc)
    log_info "Available CPUs: $num_cpus"

    # 可在此处添加CPU亲和性配置
    # 例如：将XDP进程绑定到特定核心
}

# 配置网络接口
configure_network() {
    log_info "Configuring network interface $IFACE..."

    # 启用网卡
    ip link set "$IFACE" up

    # 设置MTU（推荐使用较大MTU以减少开销）
    ip link set "$IFACE" mtu 9000

    # 如果没有IP，则自动配置
    if [[ -z "$(get_ip "$IFACE")" ]]; then
        log_info "No IP on $IFACE, auto-configuring..."
        ip addr add "$FRONTEND_IP/24" dev "$IFACE" 2>/dev/null || true
    fi

    # 配置后端网卡
    if [[ -n "$BACKEND_IFACE" ]]; then
        ip link set "$BACKEND_IFACE" up 2>/dev/null || true
        if [[ -z "$(get_ip "$BACKEND_IFACE")" ]]; then
            log_info "No IP on $BACKEND_IFACE, auto-configuring..."
            ip addr add "$BACKEND_IP/24" dev "$BACKEND_IFACE" 2>/dev/null || true
        fi
    fi

    log_info "Network interface configured"
}

# 加载XDP程序
load_xdp() {
    log_info "Loading XDP program..."

    # 检查是否已有XDP加载
    if ip link show "$IFACE" | grep -q "xdp"; then
        log_warn "XDP already loaded, detaching first..."
        ip link set "$IFACE" xdp off 2>/dev/null || true
    fi

    # 附加XDP程序（驱动模式，需要网卡支持）
    if ip link set "$IFACE" xdp obj "$BPF_OBJ" sec xdp 2>/dev/null; then
        log_info "XDP loaded in native mode"
    else
        log_warn "Native mode not supported, trying generic mode..."
        if ip link set "$IFACE" xdp obj "$BPF_OBJ" sec xdp mode generic 2>/dev/null; then
            log_info "XDP loaded in generic mode"
        else
            log_error "Failed to load XDP program"
            exit 1
        fi
    fi
}

# 添加转发规则
add_forwarding_rules() {
    log_info "Adding default forwarding rules..."

    # 添加示例规则
    $XDP_CONTROLLER -a

    log_info "Forwarding rules added"
}

# 启动XDP控制器
start_controller() {
    log_info "Starting XDP controller..."

    # 以后台模式运行
    $XDP_CONTROLLER -i "$IFACE" -r &

    # 等待启动
    sleep 2

    # 检查进程
    if pgrep -f "xdp_controller" > /dev/null; then
        log_info "XDP controller started (PID: $(pgrep -f xdp_controller))"
    else
        log_error "Failed to start XDP controller"
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    log_info "Verifying deployment..."

    # 检查XDP状态
    echo ""
    echo "=== XDP Status ==="
    ip link show "$IFACE" | grep -A 5 "xdp"

    # 显示统计信息
    echo ""
    echo "=== XDP Statistics ==="
    $XDP_CONTROLLER -s 2>/dev/null || echo "No statistics available"

    # 显示流表
    echo ""
    echo "=== Flow Table ==="
    $XDP_CONTROLLER -f 2>/dev/null || echo "No flow entries"

    log_info "Deployment verified"
}

# 停止服务
stop_service() {
    log_info "Stopping XDP services..."

    # 停止控制器
    pkill -f "xdp_controller" 2>/dev/null || true

    # 分离XDP
    ip link set "$IFACE" xdp off 2>/dev/null || true

    log_info "Services stopped"
}

# 卸载部署
uninstall() {
    log_info "Uninstalling XDP..."

    stop_service

    # 恢复系统参数
    sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true

    log_info "Uninstallation complete"
}

# 显示使用帮助
usage() {
    echo "XDP Cluster Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy     - Full deployment (default)"
    echo "  build      - Build programs only"
    echo "  load       - Load XDP program"
    echo "  start      - Start XDP controller"
    echo "  stop       - Stop services"
    echo "  verify     - Verify deployment"
    echo "  uninstall  - Uninstall XDP"
    echo "  help       - Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  IFACE          - Frontend network interface (default: eth0)"
    echo "  BACKEND_IFACE  - Backend network interface (default: eth1)"
    echo ""
    echo "Note: IP addresses are automatically detected from interfaces."
    echo "      If not found, default IPs will be used:"
    echo "      - Frontend: 192.168.88.10/24"
    echo "      - Backend:  192.168.89.10/24"
}

# 主函数
main() {
    local command="${1:-deploy}"

    case "$command" in
        deploy)
            check_root
            check_dependencies
            check_kernel_support
            detect_network_config
            build_programs
            configure_system
            configure_network
            load_xdp
            start_controller
            verify_deployment
            ;;
        build)
            check_dependencies
            build_programs
            ;;
        load)
            check_root
            check_kernel_support
            load_xdp
            ;;
        start)
            check_root
            start_controller
            ;;
        stop)
            check_root
            stop_service
            ;;
        verify)
            verify_deployment
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        help)
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
