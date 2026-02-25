# SPDX-License-Identifier: (GPL-2.0)
# Common library Makefile for XDP project

LIB_DIR = ..
XDP_TOOLS_DIR = $(LIB_DIR)/xdp-tools

# Include config from xdp-tools
include $(XDP_TOOLS_DIR)/config.mk

CFLAGS += -I$(XDP_TOOLS_DIR)/lib/libbpf/src/root_include
CFLAGS += -I$(XDP_TOOLS_DIR)/headers

# Verbose control
ifeq ($(VERBOSE),0)
Q = @
QUIET_CC = @echo '    CC       '$@;
else
Q =
QUIET_CC =
endif

all: common_params.o common_user_bpf_xdp.o

common_params.o: common_params.c common_params.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

common_user_bpf_xdp.o: common_user_bpf_xdp.c common_user_bpf_xdp.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

.PHONY: clean

clean:
	$(Q)rm -f *.o
