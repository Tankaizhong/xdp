# SPDX-License-Identifier: (GPL-2.0 OR BSD-2-Clause)
# Common Makefile parts for BPF-building with libbpf

LLC ?= llc
CLANG ?= clang
CC ?= gcc

LIB_DIR ?= ./lib
XDP_TOOLS_DIR := $(LIB_DIR)/xdp-tools

include $(LIB_DIR)/defines.mk

# Create expansions for dependencies
USER_C := ${USER_TARGETS:=.c}
USER_OBJ := ${USER_C:.c=.o}

XDP_C = ${XDP_TARGETS:=.c}
XDP_OBJ = ${XDP_C:.c=.o}

COMMON_DIR := $(LIB_DIR)/common
COMMON_OBJS := $(COMMON_DIR)/common_params.o $(COMMON_DIR)/common_user_bpf_xdp.o

# Extra includes for BPF
BPF_CFLAGS += -I$(XDP_TOOLS_DIR)/lib/libbpf/src/root_include
BPF_CFLAGS += -I$(XDP_TOOLS_DIR)/headers

# User space C flags
CFLAGS += -I$(XDP_TOOLS_DIR)/lib/libbpf/src/root_include
CFLAGS += -I$(XDP_TOOLS_DIR)/headers
CFLAGS += -I$(LIB_DIR)/common

# Link flags
LDFLAGS += -L$(XDP_TOOLS_DIR)/lib/libbpf/src
LDFLAGS += -L$(XDP_TOOLS_DIR)/lib/libxdp

# Library dependencies
LIB_OBJS = $(XDP_TOOLS_DIR)/lib/libbpf/src/libbpf.a \
	   $(XDP_TOOLS_DIR)/lib/libxdp/libxdp.a

LDLIBS += -lelf -lz -lpthread

all: lib $(USER_TARGETS) $(XDP_OBJ)

.PHONY: lib clean

lib:
	@echo "Building common library..."
	$(MAKE) -C $(COMMON_DIR)

$(LIB_OBJS):
	@echo "Ensuring libraries are built..."
	@if [ ! -f $(XDP_TOOLS_DIR)/lib/libbpf/src/libbpf.a ]; then \
		echo "Building libbpf..."; \
		$(MAKE) -C $(XDP_TOOLS_DIR)/lib/libbpf/src; \
	fi
	@if [ ! -f $(XDP_TOOLS_DIR)/lib/libxdp/libxdp.a ]; then \
		echo "Building libxdp..."; \
		$(MAKE) -C $(XDP_TOOLS_DIR)/lib/libxdp; \
	fi

$(USER_TARGETS): %: %.c $(COMMON_OBJS) $(LIB_OBJS) Makefile
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ $< $(COMMON_OBJS) $(LDLIBS)

$(XDP_OBJ): %.o: %.c Makefile
	$(QUIET_CLANG)$(CLANG) -target $(BPF_TARGET) $(BPF_CFLAGS) -O2 -c -g -o $@ $<

clean:
	$(Q)rm -f $(USER_TARGETS) $(XDP_OBJ) $(USER_OBJ) *.ll *.o
	$(MAKE) -C $(COMMON_DIR) clean
