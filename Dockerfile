FROM ubuntu:24.04

# 1. 换源（放在最顶层，几乎永不失效）
RUN sed -i 's/[a-z.]*archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources

# 2. 安装系统工具
RUN apt-get update && apt-get install -y \
    build-essential clang llvm libelf-dev iproute2 \
    pkg-config git m4 libpcap-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/xdp

# 3. 复制项目源码（使用本地构建上下文）
COPY . .

# 4. 修复所有脚本的行尾符（Windows CRLF 问题）
RUN find . -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
RUN find . -name "configure" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
RUN find lib/xdp-tools -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
RUN find lib/xdp-tools -name "configure" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

# 5. 初始化并更新 xdp-tools 的子模块（libbpf）
RUN git submodule update --init --recursive

# 6. 编译 xdp-tools
RUN cd lib/xdp-tools && \
    chmod +x configure && \
    ./configure && \
    make && \
    make install

# 7. 复制 libbpf 头文件到系统目录
RUN mkdir -p /usr/include/bpf && \
    cp lib/xdp-tools/lib/libbpf/src/*.h /usr/include/bpf/ && \
    cp -r lib/xdp-tools/headers/* /usr/include/

# 8. 编译项目
RUN make clean && make

CMD ["/bin/bash"]
