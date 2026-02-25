# SPDX-License-Identifier: (GPL-2.0 OR BSD-2-Clause)
# Common defines for XDP build

CFLAGS ?= -O2 -g
BPF_CFLAGS ?= -Wall -Wno-unused-value -Wno-pointer-sign \
	-Wno-compare-distinct-pointer-types \
	-Wno-visibility -Werror -fno-stack-protector
BPF_TARGET ?= bpf

# Include config from xdp-tools
include $(LIB_DIR)/xdp-tools/config.mk

PREFIX?=/usr/local
LIBDIR?=$(PREFIX)/lib
SBINDIR?=$(PREFIX)/sbin
HDRDIR?=$(PREFIX)/include/xdp
DATADIR?=$(PREFIX)/share
MANDIR?=$(DATADIR)/man
BPF_DIR_MNT ?=/sys/fs/bpf
BPF_OBJECT_DIR ?=$(LIBDIR)/bpf
MAX_DISPATCHER_ACTIONS ?=10

# Headers from xdp-tools
HEADER_DIR = $(XDP_TOOLS_DIR)/headers
LIBBPF_DIR := $(XDP_TOOLS_DIR)/lib/libbpf
LIBXDP_DIR := $(XDP_TOOLS_DIR)/lib/libxdp

DEFINES := -DBPF_DIR_MNT=\"$(BPF_DIR_MNT)\" -DBPF_OBJECT_PATH=\"$(BPF_OBJECT_DIR)\"

ifneq ($(PRODUCTION),1)
DEFINES += -DDEBUG
endif

CFLAGS += $(DEFINES) $(ARCH_INCLUDES)
BPF_CFLAGS += $(DEFINES) $(ARCH_INCLUDES)

# Verbose output control
ifeq ("$(origin V)", "command line")
VERBOSE = $(V)
endif
ifndef VERBOSE
VERBOSE = 0
endif
ifeq ($(VERBOSE),0)
MAKEFLAGS += --no-print-directory
Q = @
else
Q =
endif

ifeq ($(VERBOSE), 0)
    QUIET_CC       = @echo '    CC       '$@;
    QUIET_CLANG    = @echo '    CLANG    '$@;
    QUIET_LINK     = @echo '    LINK     '$@;
    QUIET_INSTALL  = @echo '    INSTALL  '$@;
endif
