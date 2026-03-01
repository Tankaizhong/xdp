#!/bin/bash
# test.sh - XDP 集群测试脚本
# 验证XDP功能和性能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
IFACE="${IFACE:-eth0}"
XDP_CONTROLLER="./xdp_controller"
TEST_DURATION=10
PPS_TARGET=1000000  # 目标PPS

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# 测试1: 检查XDP是否加载
test_xdp_loaded() {
    log_test "Test 1: Checking if XDP is loaded..."

    if ip link show "$IFACE" | grep -q "xdp"; then
        log_info "XDP is loaded on $IFACE"
        return 0
    else
        log_error "XDP is NOT loaded on $IFACE"
        return 1
    fi
}

# 测试2: 检查XDP程序统计
test_xdp_stats() {
    log_test "Test 2: Checking XDP statistics..."

    if [[ ! -f "$XDP_CONTROLLER" ]]; then
        log_error "XDP controller not found"
        return 1
    fi

    $XDP_CONTROLLER -s
    return 0
}

# 测试3: 检查流表
test_flow_table() {
    log_test "Test 3: Checking flow table..."

    if [[ ! -f "$XDP_CONTROLLER" ]]; then
        log_error "XDP controller not found"
        return 1
    fi

    $XDP_CONTROLLER -f
    return 0
}

# 测试4: 网络连通性测试
test_network_connectivity() {
    log_test "Test 4: Network connectivity test..."

    local gateways=$(ip route | grep default | awk '{print $3}' | head -1)

    if [[ -n "$gateways" ]]; then
        log_info "Default gateway: $gateways"
        if ping -c 3 -W 2 "$gateways" &> /dev/null; then
            log_info "Gateway is reachable"
        else
            log_warn "Gateway is not reachable"
        fi
    else
        log_warn "No default gateway found"
    fi

    # 测试本地网络
    local local_ips=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [[ -n "$local_ips" ]]; then
        log_info "Local IP: $local_ips"
    fi

    return 0
}

# 测试5: 性能测试 - 简单吞吐量测试
test_throughput() {
    log_test "Test 5: Throughput test..."

    # 获取初始统计
    local initial_stats=$($XDP_CONTROLLER -s 2>/dev/null || echo "0 0 0 0")
    local initial_rx=$(echo "$initial_stats" | grep "RX Packets" | awk '{print $3}')

    log_info "Starting throughput test for ${TEST_DURATION}s..."
    log_info "Target: ${PPS_TARGET} PPS"

    # 等待一段时间
    sleep "$TEST_DURATION"

    # 获取最终统计
    local final_stats=$($XDP_CONTROLLER -s 2>/dev/null || echo "0 0 0 0")
    local final_rx=$(echo "$final_stats" | grep "RX Packets" | awk '{print $3}')

    if [[ -n "$initial_rx" && -n "$final_rx" ]]; then
        local rx_diff=$((final_rx - initial_rx))
        local actual_pps=$((rx_diff / TEST_DURATION))

        log_info "RX Packets: $rx_diff (${actual_pps} PPS)"

        if [[ $actual_pps -gt 0 ]]; then
            log_info "Throughput test completed"
            return 0
        else
            log_warn "No traffic detected"
            return 1
        fi
    else
        log_error "Failed to get statistics"
        return 1
    fi
}

# 测试6: 生成测试流量
generate_traffic() {
    log_test "Test 6: Generating test traffic..."

    local target_ip="${1:-10.0.0.2}"
    local count="${2:-1000}"

    log_info "Generating $count packets to $target_ip..."

    # 使用hping3或nc生成流量（如果可用）
    if command -v hping3 &> /dev/null; then
        hping3 -c "$count" -i 1 "$target_ip" &> /dev/null || true
    elif command -v ping &> /dev/null; then
        ping -c "$count" "$target_ip" &> /dev/null || true
    fi

    # 显示统计
    $XDP_CONTROLLER -s

    return 0
}

# 测试7: 验证XDP模式
test_xdp_mode() {
    log_test "Test 7: Verifying XDP mode..."

    local xdp_info=$(ip link show "$IFACE" | grep -oP 'xdp[\w:]*')

    if [[ -n "$xdp_info" ]]; then
        log_info "XDP Mode: $xdp_info"

        if echo "$xdp_info" | grep -q "native"; then
            log_info "Running in native (driver) mode - optimal performance"
        elif echo "$xdp_info" | grep -q "generic"; then
            log_warn "Running in generic mode - lower performance"
        fi
        return 0
    else
        log_error "Cannot determine XDP mode"
        return 1
    fi
}

# 测试8: eBPF Map验证
test_ebpf_maps() {
    log_test "Test 8: Verifying eBPF maps..."

    # 列出所有bpf map
    if command -v bpftool &> /dev/null; then
        log_info "eBPF Maps:"
        bpftool map show 2>/dev/null || log_warn "Cannot list maps"
    else
        log_warn "bpftool not available"
    fi

    return 0
}

# 测试9: XDP丢包测试
test_dropped_packets() {
    log_test "Test 9: Checking for dropped packets..."

    local stats=$($XDP_CONTROLLER -s 2>/dev/null || echo "")
    local dropped=$(echo "$stats" | grep "Dropped" | awk '{print $3}')

    if [[ -n "$dropped" && "$dropped" -gt 0 ]]; then
        log_warn "Dropped packets detected: $dropped"
    else
        log_info "No dropped packets"
    fi

    return 0
}

# 测试10: 延迟测试
test_latency() {
    log_test "Test 10: Latency test..."

    # 简单延迟测试
    local count=10
    local total=0

    for i in $(seq 1 $count); do
        local start=$(date +%s%N)
        ping -c 1 -W 1 127.0.0.1 &> /dev/null
        local end=$(date +%s%N)
        local latency=$(( (end - start) / 1000 ))  # 微秒
        total=$((total + latency))
    done

    local avg=$((total / count))
    log_info "Average loopback latency: ${avg} μs"

    return 0
}

# 完整测试套件
run_all_tests() {
    log_info "========================================="
    log_info "  XDP Cluster Test Suite"
    log_info "========================================="
    echo ""

    local failed=0

    # 基础功能测试
    log_info "--- Functional Tests ---"
    test_xdp_loaded || failed=$((failed + 1))
    test_xdp_mode || failed=$((failed + 1))
    test_xdp_stats || failed=$((failed + 1))
    test_flow_table || failed=$((failed + 1))
    test_ebpf_maps || failed=$((failed + 1))
    test_network_connectivity || failed=$((failed + 1))
    test_dropped_packets || failed=$((failed + 1))

    echo ""
    log_info "--- Performance Tests ---"
    test_latency || failed=$((failed + 1))

    # 汇总结果
    echo ""
    log_info "========================================="
    if [[ $failed -eq 0 ]]; then
        log_info "All tests passed!"
    else
        log_error "$failed test(s) failed"
    fi
    log_info "========================================="

    return $failed
}

# 显示帮助
usage() {
    echo "XDP Cluster Test Script"
    echo ""
    echo "Usage: $0 [TEST] [OPTIONS]"
    echo ""
    echo "Tests:"
    echo "  all           - Run all tests (default)"
    echo "  loaded        - Check if XDP is loaded"
    echo "  stats         - Show XDP statistics"
    echo "  flow          - Show flow table"
    echo "  connectivity  - Test network connectivity"
    echo "  throughput    - Test throughput"
    echo "  mode          - Check XDP mode"
    echo "  maps          - List eBPF maps"
    echo "  dropped       - Check dropped packets"
    echo "  latency       - Test latency"
    echo ""
    echo "Options:"
    echo "  -i <iface>    Network interface (default: eth0)"
    echo "  -d <duration> Test duration in seconds (default: 10)"
    echo ""
    echo "Examples:"
    echo "  $0 all"
    echo "  $0 throughput -d 30"
    echo "  $0 stats"
}

# 主函数
main() {
    local test_name="${1:-all}"
    shift || true

    # 解析选项
    while getopts "i:d:h" opt; do
        case "$opt" in
            i) IFACE="$OPTARG" ;;
            d) TEST_DURATION="$OPTARG" ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done

    case "$test_name" in
        all)
            run_all_tests
            ;;
        loaded)
            test_xdp_loaded
            ;;
        stats)
            test_xdp_stats
            ;;
        flow)
            test_flow_table
            ;;
        connectivity)
            test_network_connectivity
            ;;
        throughput)
            test_throughput
            ;;
        mode)
            test_xdp_mode
            ;;
        maps)
            test_ebpf_maps
            ;;
        dropped)
            test_dropped_packets
            ;;
        latency)
            test_latency
            ;;
        generate)
            generate_traffic "$@"
            ;;
        help)
            usage
            ;;
        *)
            log_error "Unknown test: $test_name"
            usage
            exit 1
            ;;
    esac
}

main "$@"
