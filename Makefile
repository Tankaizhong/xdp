# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project

# Project directories
SRC_DIR := ./src
BPF_DIR := ./bpf
INCLUDE_DIR := ./include
LIB_DIR := ./lib
COMMON_DIR := ./common

# Compiler settings
CC ?= gcc
CLANG ?= clang
LLC ?= llc

CFLAGS := -Wall -O2 -g -I$(COMMON_DIR) -I$(INCLUDE_DIR)/user
LDFLAGS := -lxdp -lbpf -lelf -lz

# Targets
USER_BINARIES := xdp_user af_xdp_user

all: $(USER_BINARIES) xdp_kern.o

# User-space programs
xdp_user: $(SRC_DIR)/main/xdp_user.c $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_libbpf.o $(COMMON_DIR)/common_user_bpf_xdp.o
	$(CC) $(CFLAGS) -o $@ \
		$(SRC_DIR)/main/xdp_user.c \
		$(COMMON_DIR)/common_params.o \
		$(COMMON_DIR)/common_libbpf.o \
		$(COMMON_DIR)/common_user_bpf_xdp.o \
		$(LDFLAGS)

af_xdp_user: $(SRC_DIR)/main/af_xdp_user.c $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_libbpf.o $(COMMON_DIR)/common_user_bpf_xdp.o
	$(CC) $(CFLAGS) -o $@ \
		$(SRC_DIR)/main/af_xdp_user.c \
		$(COMMON_DIR)/common_params.o \
		$(COMMON_DIR)/common_libbpf.o \
		$(COMMON_DIR)/common_user_bpf_xdp.o \
		$(LDFLAGS)

# Common objects
$(COMMON_DIR)/%.o: $(COMMON_DIR)/%.c
	$(CC) $(CFLAGS) -I$(LIB_DIR)/install/include -c -o $@ $<

# BPF kernel program
xdp_kern.o: $(BPF_DIR)/xdp_kern.c
	$(CLANG) -target bpf -D__TARGET_ARCH_$(shell uname -m | sed 's/x86_64/x86/;s/aarch64/arm64/') \
		-I$(INCLUDE_DIR)/bpf -I$(COMMON_DIR) \
		-O2 -c -g -o $@ $<

clean:
	rm -f $(USER_BINARIES) xdp_kern.o
	rm -f $(COMMON_DIR)/*.o

rebuild: clean all

install: all
	install -m 0755 xdp_user /usr/local/bin/
	install -m 0755 af_xdp_user /usr/local/bin/
	install -m 0644 xdp_kern.o /usr/local/lib/bpf/ 2>/dev/null || true

uninstall:
	rm -f /usr/local/bin/xdp_user
	rm -f /usr/local/bin/af_xdp_user
	rm -f /usr/local/lib/bpf/xdp_kern.o 2>/dev/null || true

help:
	@echo "XDP Cluster Forwarding Project"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build everything"
	@echo "  clean     - Clean build artifacts"
	@echo "  rebuild   - Clean and rebuild"
	@echo "  install   - Install binaries"
	@echo "  uninstall - Remove installed binaries"
	@echo "  help      - Show this help"

.PHONY: all clean rebuild install uninstall help
