# SPDX-License-Identifier: (GPL-2.0)
LIB_DIR = ../lib
include $(LIB_DIR)/defines.mk

all: common_params.o common_libbpf.o common_user_bpf_xdp.o

CFLAGS += -I$(LIB_DIR)/install/include -I../include/user

common_params.o: common_params.c common_params.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

common_libbpf.o: common_libbpf.c common_libbpf.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

common_user_bpf_xdp.o: common_user_bpf_xdp.c common_user_bpf_xdp.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

.PHONY: clean

clean:
	$(Q)rm -f *.o
