#!/bin/bash

# XDP项目依赖下载脚本
# 下载预编译的libbpf库到项目目录

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBBPF_DIR="$SCRIPT_DIR/libbpf"

echo "========================================"
echo "  XDP项目 libbpf 下载脚本"
echo "========================================"
echo "项目目录: $SCRIPT_DIR"

# 检测架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# 下载libbpf
download_libbpf() {
    local version="1.4.0"
    local arch=$(detect_arch)
    local lib_dir="$LIBBPF_DIR/src"

    echo ""
    echo "下载 libbpf v$version ($arch)..."

    # 创建目录
    mkdir -p "$lib_dir"

    # 下载源码
    local tarball="v$version.tar.gz"
    local url="https://github.com/libbpf/libbpf/archive/refs/tags/$tarball"

    echo "从 GitHub 下载: $url"
    wget -q --show-progress -O "/tmp/libbpf-$tarball" "$url"

    # 解压
    echo "解压..."
    tar -xzf "/tmp/libbpf-$tarball" -C /tmp/

    # 复制源码
    rm -rf "$LIBBPF_DIR"
    mv "/tmp/libbpf-$version" "$LIBBPF_DIR"

    # 清理
    rm -f "/tmp/libbpf-$tarball"

    echo "下载完成: $LIBBPF_DIR"
}

# 编译libbpf
build_libbpf() {
    echo ""
    echo "========================================"
    echo "  编译 libbpf"
    echo "========================================"

    cd "$LIBBPF_DIR/src"

    # 清理
    make clean 2>/dev/null || true

    # 编译静态库
    echo "编译中..."
    make -j$(nproc)

    # 设置RPATH
    echo "完成!"

    cd "$SCRIPT_DIR"
}

# 检查
check_libbpf() {
    echo ""
    echo "========================================"
    echo "  检查 libbpf"
    echo "========================================"

    if [ -f "$LIBBPF_DIR/src/libbpf.a" ]; then
        echo "[OK] libbpf.a 已就绪"
        ls -lh "$LIBBPF_DIR/src/libbpf.a"
    else
        echo "[MISSING] libbpf.a 未找到"
        return 1
    fi

    if [ -f "$LIBBPF_DIR/src/bpf/libbpf.h" ]; then
        echo "[OK] 头文件已就绪"
    else
        echo "[MISSING] 头文件未找到"
        return 1
    fi

    echo ""
    echo "libbpf 已准备完毕!"
}

# 主函数
main() {
    # 检查是否已存在
    if [ -f "$LIBBPF_DIR/src/libbpf.a" ]; then
        echo "libbpf 已存在，跳过下载"
        check_libbpf
        return
    fi

    # 下载
    download_libbpf

    # 编译
    build_libbpf

    # 检查
    check_libbpf

    echo ""
    echo "========================================"
    echo "  完成!"
    echo "========================================"
    echo ""
    echo "编译项目:"
    echo "  make clean && make all"
}

# 显示帮助
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help    显示帮助"
    echo "  -c, --check   检查状态"
    echo "  -r, --rebuild 重新下载编译"
    exit 0
fi

# 重建模式
if [ "$1" = "-r" ] || [ "$1" = "--rebuild" ]; then
    rm -rf "$LIBBPF_DIR"
fi

# 检查模式
if [ "$1" = "-c" ] || [ "$1" = "--check" ]; then
    check_libbpf
else
    main
fi
