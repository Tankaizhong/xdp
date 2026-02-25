# Dockerfile for XDP Testing
# 基于 Ubuntu 22.04，使用 xdp-tools 开发

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 使用清华镜像源
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn/ubuntu|g' /etc/apt/sources.list

# 安装编译依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    llvm \
    libelf-dev \
    linux-tools-generic \
    iproute2 \
    iputils-ping \
    tcpdump \
    vim \
    curl \
    wget \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 复制项目文件
WORKDIR /workspace/xdp
COPY . .

# 复制 libbpf 头文件
RUN mkdir -p /usr/include/bpf && \
    cp lib/libbpf/src/*.h /usr/include/bpf/ 2>/dev/null || true

# 复制 xdp-tools 头文件
RUN mkdir -p /usr/include/xdp && \
    cp -r lib/xdp-tools/headers/* /usr/include/ 2>/dev/null || true

# 编译 libbpf
RUN cd lib/libbpf/src && make

# 配置 xdp-tools
RUN cd lib/xdp-tools && ./configure

# 编译 libxdp
RUN cd lib/xdp-tools/lib/libxdp && make

# 编译项目
RUN make clean && make all || echo "Build may require xdp-tools"

# 创建测试脚本
RUN echo '#!/bin/bash\necho "=== XDP Docker Test Environment ==="\necho "Available network interfaces:"\nip link show\necho ""\necho "Kernel XDP support:"\ncat /proc/config.gz 2>/dev/null | gunzip | grep -i xdp || echo "Cannot check kernel config"\necho ""\necho "Built files:"\nls -la /workspace/xdp/*.o /workspace/xdp/xdp_* 2>/dev/null\n' > /usr/local/bin/xdp-test.sh && chmod +x /usr/local/bin/xdp-test.sh

CMD ["/bin/bash"]
