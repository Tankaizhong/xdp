# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project

# Project directories
SRC_DIR := ./src
BPF_DIR := ./bpf
INCLUDE_DIR := ./include
LIB_DIR := ./lib
COMMON_DIR := ./src/lib
CONFIGS_DIR := ./configs

# Targets
USER_TARGETS := xdp_user af_xdp_user

# Include common build config
include $(CONFIGS_DIR)/common.mk

# Build lib first
lib: $(OBJECT_LIBBPF) $(OBJECT_LIBXDP)

all: lib $(USER_TARGETS) $(XDP_OBJ)

# User-space programs
$(SRC_DIR)/main/xdp_user: $(SRC_DIR)/main/xdp_user.c $(INCLUDE_DIR)/user/common.h
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -I$(INCLUDE_DIR)/user -o $@ $< $(COMMON_OBJS) $(LIB_OBJS) -lxdp -lbpf

$(SRC_DIR)/main/af_xdp_user: $(SRC_DIR)/main/af_xdp_user.c $(INCLUDE_DIR)/user/common.h
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -I$(INCLUDE_DIR)/user -o $@ $< $(COMMON_OBJS) $(LIB_OBJS) -lxdp -lbpf

# Symlinks for backwards compatibility
xdp_user: $(SRC_DIR)/main/xdp_user
	@ln -sf $< $@

af_xdp_user: $(SRC_DIR)/main/af_xdp_user
	@ln -sf $< $@

# BPF kernel program
$(BPF_DIR)/xdp_kern.o: $(BPF_DIR)/xdp_kern.c
	$(QUIET_CLANG)$(CLANG) -target $(BPF_TARGET) $(BPF_CFLAGS) -I$(INCLUDE_DIR)/bpf -O2 -c -g -o $@ $<

xdp_kern.o: $(BPF_DIR)/xdp_kern.o
	@ln -sf $< $@

clean:
	$(Q)rm -f $(BPF_DIR)/*.o $(SRC_DIR)/main/xdp_user $(SRC_DIR)/main/af_xdp_user
	$(Q)rm -f $(SRC_DIR)/lib/*.o
	$(Q)rm -f xdp_user af_xdp_user xdp_kern.o *.o

rebuild: clean all

install: all
	install -m 0755 $(SRC_DIR)/main/xdp_user /usr/local/bin/
	install -m 0755 $(SRC_DIR)/main/af_xdp_user /usr/local/bin/
	install -m 0644 $(BPF_DIR)/xdp_kern.o /usr/local/lib/bpf/ 2>/dev/null || true

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
