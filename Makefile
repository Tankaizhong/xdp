# Makefile for XDP Cluster Forwarding Project

# 项目目录
SCRIPT_DIR := $(shell pwd)
LIBBPF_DIR := $(SCRIPT_DIR)/lib/libbpf

# 编译器
CC = clang
LD = ld

# 编译选项 - 使用本地libbpf
CFLAGS = -Wall -O2 -g -I$(LIBBPF_DIR)/src -I/usr/include
LDFLAGS = -lelf -lpthread -lz $(LIBBPF_DIR)/src/libbpf.a

# 目标文件
TARGET = xdp_controller
AF_XDP_TARGET = af_xdp_forwarder
BPF_TARGET = xdp_kern.o

# BPF编译选项
BPF_CFLAGS = -Wno-unused-value -Wno-pointer-sign \
             -Wno-compare-distinct-pointer-types \
             -D__TARGET_ARCH_$(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/') \
             -I$(LIBBPF_DIR)/src -I/usr/include/$(shell uname -m | sed 's/x86_64/x86_64-linux-gnu/' | sed 's/aarch64/aarch64-linux-gnu/')

# 头文件
HEADERS = common.h

# 默认目标
all: $(BPF_TARGET) $(TARGET) $(AF_XDP_TARGET)

# 编译BPF程序
$(BPF_TARGET): xdp_kern.c $(HEADERS)
	@echo "Building BPF object..."
	$(CC) $(BPF_CFLAGS) -target bpf -c $< -o $@
	@echo "BPF object built: $@"

# 编译用户态控制器
$(TARGET): xdp_user.c $(HEADERS)
	@echo "Building XDP controller..."
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "XDP controller built: $@"

# 编译AF_XDP程序
$(AF_XDP_TARGET): af_xdp_user.c $(HEADERS)
	@echo "Building AF_XDP forwarder..."
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "AF_XDP forwarder built: $@"

# 清理
clean:
	rm -f $(BPF_TARGET) $(TARGET) $(AF_XDP_TARGET)
	rm -f *.o

# 安装
install: all
	@echo "Installing XDP programs..."
	cp $(TARGET) /usr/local/bin/
	cp $(AF_XDP_TARGET) /usr/local/bin/
	@echo "Installation complete"

# 卸载
uninstall:
	rm -f /usr/local/bin/$(TARGET)
	rm -f /usr/local/bin/$(AF_XDP_TARGET)
	@echo "Uninstallation complete"

# 重新编译
rebuild: clean all

# 下载并编译依赖
deps:
	@echo "下载 libbpf..."
	./脚本.sh

# 帮助
help:
	@echo "XDP Cluster Forwarding Project"
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build all targets (default)"
	@echo "  $(BPF_TARGET)   - Build BPF object"
	@echo "  $(TARGET)      - Build XDP controller"
	@echo "  $(AF_XDP_TARGET) - Build AF_XDP forwarder"
	@echo "  clean       - Remove built files"
	@echo "  install     - Install binaries"
	@echo "  uninstall   - Uninstall binaries"
	@echo "  rebuild     - Clean and rebuild"
	@echo "  deps        - Download and build libbpf"
	@echo ""
	@echo "Usage:"
	@echo "  make deps               # Download libbpf"
	@echo "  make                    # Build everything"
	@echo "  make clean              # Clean build artifacts"

.PHONY: all clean install uninstall rebuild help deps
