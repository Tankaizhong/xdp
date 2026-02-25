# Dockerfile for XDP Testing
# 基于 Ubuntu 22.04，支持 XDP 开发

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 安装编译依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    llvm \
    libelf-dev \
    libbpf-dev \
    linux-tools-generic \
    iproute2 \
    iputils-ping \
    tcpdump \
    vim \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 复制项目文件
WORKDIR /workspace/xdp
COPY . .

# 复制 libbpf 头文件
RUN mkdir -p /usr/include/bpf && \
    cp lib/libbpf/src/*.h /usr/include/bpf/ 2>/dev/null || true

# 编译 libbpf
RUN cd lib/libbpf/src && make

# 编译项目
RUN make clean && make all || echo "Build may require libbpf"

# 创建测试脚本
RUN echo '#!/bin/bash\n\
echo "=== XDP Docker Test Environment ==="\n\
echo "Available network interfaces:"\n\
ip link show\n\
echo ""\n\
echo "Kernel XDP support:"\n\
cat /proc/config.gz 2>/dev/null | gunzip | grep -i xdp || echo "Cannot check kernel config"\n\
' > /usr/local/bin/xdp-test.sh && chmod +x /usr/local/bin/xdp-test.sh

CMD ["/bin/bash"]
