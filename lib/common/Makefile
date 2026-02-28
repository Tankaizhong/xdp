# SPDX-License-Identifier: (GPL-2.0)
# Common library Makefile

all: common_params.o common_user_bpf_xdp.o

common_params.o: common_params.c common_params.h
	$(CC) $(CFLAGS) -c -o $@ $<

common_user_bpf_xdp.o: common_user_bpf_xdp.c common_user_bpf_xdp.h
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f *.o

.PHONY: clean
