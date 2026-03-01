# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project

# Project directories
COMMON_DIR := ./common
LIB_DIR := ./lib

# Targets
XDP_TARGETS := xdp_kern
USER_TARGETS := xdp_user af_xdp_user

include $(COMMON_DIR)/common.mk

# Build lib first (creates install/ directory with headers)
lib: $(OBJECT_LIBBPF) $(OBJECT_LIBXDP)

all: lib $(USER_TARGETS) $(XDP_OBJ)

xdp_user: xdp_user.c common.h
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ $< $(COMMON_OBJS) $(LIB_OBJS) $(LDLIBS)

af_xdp_user: af_xdp_user.c common.h
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ $< $(COMMON_OBJS) $(LIB_OBJS) $(LDLIBS)

xdp_kern.o: xdp_kern.c
	$(QUIET_CLANG)$(CLANG) -target $(BPF_TARGET) $(BPF_CFLAGS) -O2 -c -g -o $@ $<

clean:
	$(Q)rm -f xdp_kern.o xdp_user af_xdp_user *.o $(COMMON_DIR)/*.o

rebuild: clean all

install: all
	install -m 0755 xdp_user /usr/local/bin/
	install -m 0755 af_xdp_user /usr/local/bin/
	install -m 0644 xdp_kern.o /usr/local/lib/bpf/ 2>/dev/null || true

help:
	@echo "XDP Cluster Forwarding Project"
	@echo "Targets: all, lib, clean, rebuild, install"

.PHONY: all lib clean rebuild install help
