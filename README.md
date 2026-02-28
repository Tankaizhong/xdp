# XDP Cluster Forwarding Project

A high-performance cluster forwarding system based on eBPF/XDP.

## Features

- XDP (Express Data Path) for high-performance packet processing
- AF_XDP support for zero-copy forwarding
- Flow-based hash table lookup
- IPv4/IPv6 support
- TCP/UDP port extraction

## Build

```bash
# Install dependencies
sudo apt-get install build-essential clang llvm libelf-dev iproute2 git

# Clone and build
git clone https://github.com/Tankaizhong/xdp.git
cd xdp
git submodule update --init --recursive
make
```

## Usage

```bash
# Deploy XDP program
sudo ./deploy.sh deploy

# Or step by step
sudo ./deploy.sh build    # Build programs
sudo ./deploy.sh load     # Load XDP to interface
sudo ./deploy.sh start   # Start controller

# Show statistics
./xdp_user -s

# Show flow table
./xdp_user -f
```

## Project Structure

```
xdp/
├── lib/
│   ├── common/       # Common library
│   ├── libbpf/       # libbpf static library
│   ├── libxdp/       # libxdp static library
│   └── xdp-tools/    # xdp-tools (submodule)
├── xdp_kern.c        # XDP kernel program
├── xdp_user.c        # XDP controller
├── af_xdp_user.c     # AF_XDP forwarder
├── common.h          # Common definitions
├── deploy.sh         # Deployment script
├── test.sh           # Test script
└── Makefile          # Build file
```

## Requirements

- Linux kernel 5.4+ with XDP support
- clang and llvm
- libelf-dev

## License

GPL-2.0
