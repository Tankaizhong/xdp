# SPDX-License-Identifier: GPL-2.0
# Dockerfile for XDP Cluster Forwarding Project
# Build: docker build -t xdp-cluster .
# Run:   docker run --privileged -it xdp-cluster

FROM ubuntu:24.04

# Use Tsinghua mirror for faster downloads in China
RUN sed -i 's/[a-z.]*archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    llvm \
    libelf-dev \
    iproute2 \
    pkg-config \
    git \
    m4 \
    zlib1g-dev \
    sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/xdp

# Copy project source
COPY . .

# Fix shell script line endings
RUN find . -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

# Initialize git submodules (xdp-tools for headers)
RUN if [ -f .gitmodules ]; then \
        git submodule update --init --recursive; \
    fi

# Configure xdp-tools if needed
RUN if [ ! -f lib/xdp-tools/config.mk ]; then \
        cd lib/xdp-tools && \
        chmod +x configure && \
        ./configure; \
    fi

# Build local libbpf and libxdp libraries
RUN make -C lib/xdp-tools/lib/libbpf/src CFLAGS="-fPIC -O2"
RUN make -C lib/xdp-tools/lib/libxdp

# Copy built libs to local lib directory
RUN cp lib/xdp-tools/lib/libxdp/libxdp.a lib/libxdp/ && \
    cp lib/xdp-tools/lib/libbpf/src/libbpf.a lib/libbpf/src/

# Build project with local libs
RUN make clean || true
RUN make

# Install XDP programs
RUN make install

# Default command
CMD ["/bin/bash"]
