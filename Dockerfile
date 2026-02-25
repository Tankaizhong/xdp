FROM ubuntu:24.04

# 1. 换源（放在最顶层，几乎永不失效）
RUN sed -i 's/[a-z.]*archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources

# 2. 安装系统工具（利用缓存）
RUN apt-get update && apt-get install -y \
    build-essential clang llvm libelf-dev iproute2 \
    pkg-config git m4 libpcap-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/xdp

# 3. 复制本地 xdp-tools 并编译（不克隆）
COPY lib/xdp-tools /workspace/xdp/lib/xdp-tools
RUN cd /workspace/xdp/lib/xdp-tools && \
    git submodule update --init --recursive && \
    ./configure && \
    make && \
    make install

# 4. 复制项目源码
COPY . .

# 5. 只编译你自己的项目
RUN make clean && make

CMD ["/bin/bash"]