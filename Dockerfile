# SPDX-License-Identifier: GPL-2.0
# Dockerfile for XDP Cluster Forwarding Project

FROM ubuntu:24.04

# 1. 使用清华源（提高国内下载速度）
RUN sed -i 's/[a-z.]*archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources

# 2. 安装构建依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    llvm \
    libelf-dev \
    iproute2 \
    pkg-config \
    git \
    m4 \
    libpcap-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/xdp

# 3. 复制项目源码
COPY . .

# 4. 修复脚本行尾符（避免 CRLF 问题）
RUN find . -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
RUN find lib/xdp-tools -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

# 5. 初始化并更新 git 子模块（xdp-tools）
RUN if [ -f .gitmodules ]; then \
        git submodule update --init --recursive; \
    fi

# 6. 配置 xdp-tools（如未配置）
RUN if [ ! -f lib/xdp-tools/config.mk ]; then \
        cd lib/xdp-tools && \
        chmod +x configure && \
        ./configure; \
    fi

# 7. 编译 xdp-tools（libbpf, libxdp 等）
RUN make -C lib/xdp-tools/lib/libbpf/src
RUN make -C lib/xdp-tools/lib/libxdp

# 8. 编译项目
RUN make clean || true
RUN make

# 9. 安装 XDP 程序到系统
RUN make install

# 默认启动命令
CMD ["/bin/bash"]
