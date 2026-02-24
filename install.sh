#!/bin/bash

# XDP项目依赖安装脚本

set -e

echo "========================================"
echo "  XDP项目依赖安装脚本"
echo "========================================"

# 检测Linux发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                echo "ubuntu"
                ;;
            centos|rhel|rocky|alma)
                echo "centos"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# Ubuntu/Debian 安装
install_ubuntu() {
    echo "检测到 Ubuntu/Debian 系统"
    echo "正在更新软件包列表..."

    sudo apt-get update

    echo "正在安装编译工具和依赖..."
    sudo apt-get install -y \
        clang \
        llvm \
        make \
        gcc \
        libbpf-dev \
        pkg-config \
        linux-headers-$(uname -r) \
        libelf-dev \
        libc6-dev \
        binutils-dev \
        python3

    echo "依赖安装完成!"
}

# CentOS/RHEL 安装
install_centos() {
    echo "检测到 CentOS/RHEL 系统"
    echo "正在安装编译工具和依赖..."

    sudo yum install -y \
        clang \
        llvm \
        make \
        gcc \
        pkgconfig \
        elfutils-libelf-devel \
        elfutils-devel \
        python3

    # 根据不同版本安装libbpf
    if command -v dnf &> /dev/null; then
        sudo dnf install -y libbpf-devel kernel-headers-$(uname -r)
    else
        sudo yum install -y libbpf-devel kernel-headers-$(uname -r)
    fi

    echo "依赖安装完成!"
}

# 检查依赖是否已安装
check_dependencies() {
    echo ""
    echo "========================================"
    echo "  检查依赖"
    echo "========================================"

    local missing=0

    check_cmd() {
        if command -v "$1" &> /dev/null; then
            echo "[OK] $1 已安装: $($1 --version 2>/dev/null | head -1 || echo "installed")"
        else
            echo "[MISSING] $1 未安装"
            missing=1
        fi
    }

    check_cmd clang
    check_cmd llvm-config || check_cmd llvm-config-14 || check_cmd llvm-config-15 || check_cmd llvm-config-16
    check_cmd make
    check_cmd gcc || check_cmd gcc-minimal
    check_cmd pkg-config

    # 检查libbpf
    if pkg-config --exists libbpf 2>/dev/null; then
        echo "[OK] libbpf 已安装: $(pkg-config --modversion libbpf)"
    else
        echo "[MISSING] libbpf 未安装"
        missing=1
    fi

    # 检查内核头文件
    if [ -d "/lib/modules/$(uname -r)/build" ]; then
        echo "[OK] 内核头文件已安装: $(uname -r)"
    else
        echo "[MISSING] 内核头文件未安装"
        missing=1
    fi

    if [ $missing -eq 0 ]; then
        echo ""
        echo "所有依赖已安装!"
    else
        echo ""
        echo "部分依赖缺失，请运行本脚本安装"
    fi
}

# 主函数
main() {
    local os_type=$(detect_os)

    case "$os_type" in
        ubuntu)
            install_ubuntu
            ;;
        centos)
            install_centos
            ;;
        *)
            echo "不支持的操作系统，请手动安装依赖"
            echo ""
            echo "Ubuntu/Debian:"
            echo "  sudo apt-get update"
            echo "  sudo apt-get install -y clang llvm make gcc libbpf-dev pkg-config linux-headers-\$(uname -r)"
            echo ""
            echo "CentOS/RHEL:"
            echo "  sudo yum install -y clang llvm make gcc pkgconfig"
            echo "  sudo yum install -y libbpf-devel kernel-headers"
            exit 1
            ;;
    esac

    # 验证安装
    check_dependencies
}

# 显示帮助
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help    显示帮助信息"
    echo "  -c, --check   仅检查依赖状态"
    echo ""
    echo "示例:"
    echo "  $0            安装所有依赖"
    echo "  $0 --check    检查依赖是否已安装"
    exit 0
fi

# 检查模式
if [ "$1" = "-c" ] || [ "$1" = "--check" ]; then
    check_dependencies
else
    main
fi
