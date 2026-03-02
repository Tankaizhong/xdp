# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project

# Project directories
SRC_DIR := ./src
BPF_DIR := ./bpf
COMMON_DIR := ./src/common

# Compiler settings (use system libbpf)
CC ?= gcc
CLANG ?= clang

CFLAGS := -Wall -O2 -g -I$(COMMON_DIR) -I/usr/include/bpf
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

# Common objects
$(COMMON_DIR)/%.o: $(COMMON_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Symlinks
xdp_user: $(SRC_DIR)/main/xdp_user
	ln -sf $< $@

af_xdp_user: $(SRC_DIR)/main/af_xdp_user
	ln -sf $< $@

# BPF kernel program (use system headers via pkg-config or defaults)
xdp_kern.o: $(BPF_DIR)/xdp_kern.c
	$(CLANG) -target bpf -D__TARGET_ARCH_$$(uname -m | sed 's/x86_64/x86/;s/aarch64/arm64/') \
		-I$(COMMON_DIR) \
		-I/usr/include \
		-O2 -c -g -o $@ $<

clean:
	rm -f $(USER_TARGETS) xdp_kern.o
	rm -f $(SRC_DIR)/main/xdp_user $(SRC_DIR)/main/af_xdp_user
	rm -f $(COMMON_DIR)/*.o
	rm -f xdp_user af_xdp_user

rebuild: clean all

install: all
	install -m 0755 xdp_user /usr/local/bin/
	install -m 0755 af_xdp_user /usr/local/bin/

help:
	@echo "XDP Cluster Forwarding Project"
	@echo "Targets: all, clean, rebuild, install"

.PHONY: all clean rebuild install help
