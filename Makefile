# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project

# Project directories
LIB_DIR = ./lib
COMMON_DIR = $(LIB_DIR)/common
LIBBPF_DIR = $(LIB_DIR)/libbpf
LIBXDP_DIR = $(LIB_DIR)/libxdp
XDP_TOOLS_DIR = $(LIB_DIR)/xdp-tools

# Toolchain
CC ?= gcc
CLANG ?= clang

# Verbose control
ifeq ("$(origin V)", "command line")
VERBOSE = $(V)
endif
ifndef VERBOSE
VERBOSE = 0
endif
ifeq ($(VERBOSE),0)
MAKEFLAGS += --no-print-directory
Q = @
QUIET_CC = @echo '    CC       '$@;
QUIET_CLANG = @echo '    CLANG    '$@;
else
Q =
QUIET_CC =
QUIET_CLANG =
endif

# BPF kernel object - use xdp-tools + libbpf headers
BPF_CFLAGS = -I$(XDP_TOOLS_DIR)/lib/libbpf/src/root_include -I$(XDP_TOOLS_DIR)/headers $(ARCH_INCLUDES)

# User-space programs - use system headers
CFLAGS = -I$(COMMON_DIR) -Wall

# Link flags - use LOCAL static libraries
LDFLAGS = -L$(LIBBPF_DIR)/src -L$(LIBXDP_DIR)
LDLIBS = -l:libxdp.a -l:libbpf.a -lelf -lz -lpthread

# Objects
COMMON_OBJS = $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_user_bpf_xdp.o
LIB_OBJS = $(LIBXDP_DIR)/libxdp.a $(LIBBPF_DIR)/src/libbpf.a

all: lib xdp_user af_xdp_user xdp_kern.o

lib:
	$(MAKE) -C $(COMMON_DIR)

xdp_kern.o: xdp_kern.c $(LIB_OBJS) Makefile
	$(QUIET_CLANG)$(CLANG) -target bpf $(BPF_CFLAGS) -O2 -c -g -o $@ $<

xdp_user: xdp_user.c common.h $(COMMON_OBJS) $(LIB_OBJS) Makefile
	$(QUIET_CC)$(CC) $(CFLAGS) $(LDFLAGS) -o $@ xdp_user.c $(COMMON_OBJS) $(LDLIBS)

af_xdp_user: af_xdp_user.c common.h $(COMMON_OBJS) $(LIB_OBJS) Makefile
	$(QUIET_CC)$(CC) $(CFLAGS) $(LDFLAGS) -o $@ af_xdp_user.c $(COMMON_OBJS) $(LDLIBS)

clean:
	$(Q)rm -f xdp_kern.o xdp_user af_xdp_user *.o $(COMMON_DIR)/*.o

rebuild: clean all

install: all
	install -m 0755 xdp_user /usr/local/bin/
	install -m 0755 af_xdp_user /usr/local/bin/
	install -m 0644 xdp_kern.o /usr/local/lib/bpf/ 2>/dev/null || true

help:
	@echo "XDP Cluster Forwarding Project"

.PHONY: all lib clean rebuild install help
