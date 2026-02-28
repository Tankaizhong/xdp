# SPDX-License-Identifier: GPL-2.0
# Makefile for XDP Cluster Forwarding Project
# Uses local libbpf and libxdp from xdp-tools submodule

# Project directories
LIB_DIR = ./lib
XDP_TOOLS_DIR = $(LIB_DIR)/xdp-tools
COMMON_DIR = $(LIB_DIR)/common

# Toolchain
CC ?= gcc
CLANG ?= clang

# Define targets
XDP_TARGETS = xdp_kern
USER_TARGETS = xdp_user af_xdp_user

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

# Include config from xdp-tools
include $(XDP_TOOLS_DIR)/config.mk

# Extra includes - use local xdp-tools headers
BPF_CFLAGS += -I$(XDP_TOOLS_DIR)/lib/libbpf/src/root_include
BPF_CFLAGS += -I$(XDP_TOOLS_DIR)/headers
BPF_CFLAGS += $(ARCH_INCLUDES)

CFLAGS += -I$(XDP_TOOLS_DIR)/lib/libbpf/src/root_include
CFLAGS += -I$(XDP_TOOLS_DIR)/headers
CFLAGS += -I$(COMMON_DIR)

# Link flags - use LOCAL libraries from xdp-tools (not system)
LDFLAGS += -L$(XDP_TOOLS_DIR)/lib/libbpf/src
LDFLAGS += -L$(XDP_TOOLS_DIR)/lib/libxdp

# Static link with local libraries (order matters: libxdp depends on libbpf)
LDLIBS += -l:libxdp.a -l:libbpf.a -lelf -lz -lpthread

# Common objects
COMMON_OBJS = $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_user_bpf_xdp.o

# Library objects - use local libbpf and libxdp
LIB_OBJS = $(XDP_TOOLS_DIR)/lib/libxdp/libxdp.a \
	   $(XDP_TOOLS_DIR)/lib/libbpf/src/libbpf.a

# Create expansions
XDP_OBJ = xdp_kern.o

# Default target
all: lib $(USER_TARGETS) $(XDP_OBJ)

# Build common library
lib:
	@echo "Building common library..."
	$(MAKE) -C $(COMMON_DIR)

# Ensure libbpf is built
$(XDP_TOOLS_DIR)/lib/libbpf/src/libbpf.a:
	@echo "Building libbpf..."
	$(MAKE) -C $(XDP_TOOLS_DIR)/lib/libbpf/src

# Ensure libxdp is built
$(XDP_TOOLS_DIR)/lib/libxdp/libxdp.a:
	@echo "Building libxdp..."
	$(MAKE) -C $(XDP_TOOLS_DIR)/lib/libxdp

# Ensure xdp-tools is configured
$(XDP_TOOLS_DIR)/config.mk:
	@echo "Configuring xdp-tools..."
	cd $(XDP_TOOLS_DIR) && ./configure

# Build BPF object
xdp_kern.o: xdp_kern.c $(LIB_OBJS) Makefile
	$(QUIET_CLANG)$(CLANG) -target bpf $(BPF_CFLAGS) -O2 -c -g -o $@ $<

# Build xdp_user
xdp_user: xdp_user.c common.h $(COMMON_OBJS) $(LIB_OBJS) Makefile
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ xdp_user.c $(COMMON_OBJS) $(LDLIBS)

# Build af_xdp_user
af_xdp_user: af_xdp_user.c common.h $(COMMON_OBJS) $(LIB_OBJS) Makefile
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ af_xdp_user.c $(COMMON_OBJS) $(LDLIBS)

# Clean
clean:
	$(Q)rm -f xdp_kern.o xdp_user af_xdp_user *.o
	$(Q)rm -f $(COMMON_DIR)/*.o
	@echo "Clean complete"

# Force rebuild
rebuild: clean all

# Install
install: all
	@echo "Installing XDP programs..."
	install -m 0755 xdp_user /usr/local/bin/
	install -m 0755 af_xdp_user /usr/local/bin/
	install -m 0644 xdp_kern.o /usr/local/lib/bpf/ 2>/dev/null || true
	@echo "Installation complete"

# Help
help:
	@echo "XDP Cluster Forwarding Project"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build all targets (default)"
	@echo "  lib          - Build common library"
	@echo "  xdp_kern.o   - Build BPF object"
	@echo "  xdp_user     - Build XDP controller"
	@echo "  af_xdp_user  - Build AF_XDP forwarder"
	@echo "  clean        - Remove built files"
	@echo "  rebuild      - Clean and rebuild"
	@echo "  install      - Install binaries"
	@echo ""
	@echo "Usage:"
	@echo "  make              # Build everything"
	@echo "  make V=1          # Verbose build"
	@echo "  make clean        # Clean build artifacts"
	@echo "  make rebuild      # Clean and rebuild"
	@echo ""
	@echo "Note: This Makefile uses local libbpf and libxdp from"
	@echo "      lib/xdp-tools submodule. No system dependencies required."

.PHONY: all lib clean rebuild install help
