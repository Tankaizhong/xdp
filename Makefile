# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project
# Simplified version - uses system libbpf/libxdp

# Project directories
SRC_DIR := ./src
BPF_DIR := ./bpf
COMMON_DIR := ./src/common
LIB_DIR := ./lib

# Compiler settings
CC ?= gcc
CLANG ?= clang

CFLAGS := -Wall -O2 -g -I$(COMMON_DIR) -I$(LIB_DIR)/install/include
LDFLAGS := -lxdp -lbpf -lelf -lz

# Targets
USER_TARGETS := xdp_user af_xdp_user

all: $(USER_TARGETS) xdp_kern.o

# User-space programs
$(SRC_DIR)/main/xdp_user: $(SRC_DIR)/main/xdp_user.c $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_libbpf.o $(COMMON_DIR)/common_user_bpf_xdp.o
	$(CC) $(CFLAGS) -o $@ \
		$(SRC_DIR)/main/xdp_user.c \
		$(COMMON_DIR)/common_params.o \
		$(COMMON_DIR)/common_libbpf.o \
		$(COMMON_DIR)/common_user_bpf_xdp.o \
		$(LDFLAGS)

$(SRC_DIR)/main/af_xdp_user: $(SRC_DIR)/main/af_xdp_user.c $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_libbpf.o $(COMMON_DIR)/common_user_bpf_xdp.o
	$(CC) $(CFLAGS) -o $@ \
		$(SRC_DIR)/main/af_xdp_user.c \
		$(COMMON_DIR)/common_params.o \
		$(COMMON_DIR)/common_libbpf.o \
		$(COMMON_DIR)/common_user_bpf_xdp.o \
		$(LDFLAGS)

# Symlinks for backward compatibility
xdp_user: $(SRC_DIR)/main/xdp_user
	@ln -sf $< $@

af_xdp_user: $(SRC_DIR)/main/af_xdp_user
	@ln -sf $< $@

# Common objects
$(COMMON_DIR)/%.o: $(COMMON_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

# BPF kernel program
# Use xdp-tools headers for BPF compilation
ARCH := $(shell uname -m | sed 's/x86_64/x86/;s/aarch64/arm64/')
MULTIARCH := $(shell gcc -print-multiarch 2>/dev/null || echo "x86_64-linux-gnu")
BPF_CFLAGS := -D__TARGET_ARCH_$(ARCH) \
	-I./include \
	-I./include/xdp \
	-I./include/bpf \
	-I./include/bpf/uapi \
	-I./include/bpf/linux \
	-I./include/bpf/asm \
	-I./src/common \
	-I./lib/xdp-tools/headers \
	-I./lib/libbpf/include \
	-I./lib/libbpf/src \
	-I/usr/include/$(MULTIARCH) \
	-I/usr/include \
	-O2 -g

xdp_kern.o: $(BPF_DIR)/xdp_kern.c
	$(CLANG) -target bpf $(BPF_CFLAGS) -c -g -o $@ $<

clean:
	rm -f $(USER_TARGETS) xdp_kern.o
	rm -f $(SRC_DIR)/main/xdp_user $(SRC_DIR)/main/af_xdp_user
	rm -f $(COMMON_DIR)/*.o
	rm -f xdp_user af_xdp_user

rebuild: clean all

install: all
	install -m 0755 xdp_user /usr/local/bin/
	install -m 0755 af_xdp_user /usr/local/bin/
	install -m 0644 xdp_kern.o /usr/local/lib/bpf/ 2>/dev/null || true

help:
	@echo "XDP Cluster Forwarding Project"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build everything"
	@echo "  clean     - Clean build artifacts"
	@echo "  rebuild   - Clean and rebuild"
	@echo "  install   - Install binaries"
	@echo "  help      - Show this help"

.PHONY: all clean rebuild install help
