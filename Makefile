# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project
#
# This Makefile maintains backward compatibility with the original build system
# while supporting the new directory structure via symlinks

# Project directories (new structure)
SRC_DIR := ./src
BPF_DIR := ./bpf
INCLUDE_DIR := ./include
LIB_DIR := ./lib

# Legacy directories (for backward compatibility via symlinks)
COMMON_DIR := ./common

# Targets
XDP_TARGETS := xdp_kern
USER_TARGETS := xdp_user af_xdp_user

include $(COMMON_DIR)/common.mk

# Add include path for backward compatibility
CFLAGS += -I$(COMMON_DIR) -I$(INCLUDE_DIR)/user

# Build lib first (creates install/ directory with headers)
lib: $(OBJECT_LIBBPF) $(OBJECT_LIBXDP)

all: lib $(USER_TARGETS) $(XDP_OBJ)

xdp_user: $(SRC_DIR)/main/xdp_user.c $(COMMON_DIR)/common.h
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ $< $(COMMON_OBJS) $(LIB_OBJS) -lxdp -lbpf

af_xdp_user: $(SRC_DIR)/main/af_xdp_user.c $(COMMON_DIR)/common.h
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ $< $(COMMON_OBJS) $(LIB_OBJS) -lxdp -lbpf

xdp_kern.o: $(BPF_DIR)/xdp_kern.c
	$(QUIET_CLANG)$(CLANG) -target $(BPF_TARGET) $(BPF_CFLAGS) -I$(INCLUDE_DIR)/bpf -I$(COMMON_DIR) -O2 -c -g -o $@ $<

clean:
	$(Q)rm -f $(BPF_DIR)/xdp_kern.o $(SRC_DIR)/main/xdp_user $(SRC_DIR)/main/af_xdp_user
	$(Q)rm -f xdp_kern.o xdp_user af_xdp_user *.o $(COMMON_DIR)/*.o

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
	@echo "  all       - Build everything (default)"
	@echo "  lib       - Build libbpf and libxdp"
	@echo "  clean     - Clean build artifacts"
	@echo "  rebuild   - Clean and rebuild"
	@echo "  install   - Install binaries"
	@echo "  uninstall - Remove installed binaries"
	@echo "  help      - Show this help"

.PHONY: all lib clean rebuild install uninstall help
