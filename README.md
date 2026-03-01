# XDP Cluster Forwarding Project

A high-performance cluster forwarding system based on eBPF/XDP.

## Why XDP?

XDP (Express Data Path) is a Linux kernel feature that allows programmable packet processing at the earliest possible point in the network stack - before the kernel's main networking stack processes the packet. This provides near-native performance for packet forwarding.

### Key Features

- **Drop-in kernel bypass** - Process packets before kernel networking stack
- **Zero-copy forwarding** - Using AF_XDP for direct DMA to userspace
- **Flow-based distribution** - Using RSS-like hash for load balancing
- **In-kernel acceleration** - Using eBPF maps for fast lookups

### Use Cases

- Load balancers (L4/L7)
- DDoS mitigation
- Firewalling
- Network traffic analysis
- Service mesh sidecars

## Network Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Internet                                    │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  │ Packets
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         eth0 (Frontend)                                  │
│                    XDP Load Balancer (xdp_kern.o)                        │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                        XDP Program                                 │   │
│  │                                                                   │   │
│  │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │   │
│  │   │  Parse      │───▶│  Lookup     │───▶│  Redirect   │         │   │
│  │   │  Packet     │    │  Flow Table │    │  to Backend │         │   │
│  │   └─────────────┘    └─────────────┘    └─────────────┘         │   │
│  │         │                  │                                       │   │
│  │         ▼                  ▼                                       │   │
│  │   ┌─────────────┐    ┌─────────────┐                              │   │
│  │   │  Extract    │    │  Update     │                              │   │
│  │   │  5-tuple    │    │  Statistics │                              │   │
│  │   └─────────────┘    └─────────────┘                              │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
                    ▼             ▼             ▼
              ┌──────────┐ ┌──────────┐ ┌──────────┐
              │ Backend 1 │ │ Backend 2 │ │ Backend N │
              │  :8080    │ │  :8080    │ │  :8080    │
              └──────────┘ └──────────┘ └──────────┘
```

### Components

| Component | Description |
|-----------|-------------|
| **eth0** | Frontend network interface receiving external traffic |
| **XDP Program (xdp_kern.o)** | eBPF program loaded into kernel, processes packets at wire speed |
| **Flow Table** | eBPF map storing active connections and backend selection |
| **Backend Servers** | Real backend services handling requests |

## How It Works

### Packet Processing Flow

```
┌─────────────────┐
│   Packet Received│
│   at Network Card │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  XDP Hook       │  ← First chance to process packets
│  (Driver Level) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Parse Packet   │  ← Extract headers (Ethernet, IP, TCP/UDP)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Flow Lookup    │  ← Check if connection exists in flow table
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌───────┐
│  New  │ │Known  │
│Flow   │ │Flow   │
└───┬───┘ └───┬───┘
    │         │
    ▼         ▼
┌───────────┐ ┌───────────┐
│Select     │ │Get Backend│
│Backend    │ │from Map   │
│(RR/Hash)  │ │           │
└───┬───────┘ └─────┬─────┘
    │               │
    └───────┬───────┘
            │
            ▼
┌─────────────────┐
│  Redirect       │  ← Send to backend via XDP_TX or devmap
│  to Backend     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Update Stats   │  ← Record packet/byte counts
└─────────────────┘
```

### Step-by-Step Workflow

1. **Packet Arrival**
   - Network card receives packet
   - XDP program gets first access to packet data

2. **Header Parsing**
   - Parse Ethernet header → get protocol type
   - Parse IP header → get src/dst IP
   - Parse TCP/UDP header → get src/dst ports
   - Extract 5-tuple: (protocol, src_ip, dst_ip, src_port, dst_port)

3. **Flow Table Lookup**
   - Use 5-tuple hash to look up in eBPF map
   - If found → use existing backend
   - If not found → select new backend using round-robin or hash

4. **Backend Selection**
   - Round-robin: distribute across backends evenly
   - Source hash: ensure same client goes to same backend
   - Least connections: track active connections per backend

5. **Packet Redirect**
   - Use XDP redirect to send packet to backend
   - Can redirect to:
     - Another interface (XDP_TX)
     - BPF devmap (virtual interface)
     - AF_XDP socket (userspace)

6. **Statistics Update**
   - Increment packet count
   - Update byte count
   - Update connection tracking

## Project Structure

```
xdp/
├── lib/
│   ├── common/       # Common library
│   ├── libbpf/       # libbpf static library
│   ├── libxdp/       # libxdp static library
│   └── xdp-tools/    # xdp-tools (submodule)
├── xdp_kern.c        # XDP kernel program (runs in kernel)
├── xdp_user.c        # XDP controller (userspace)
├── af_xdp_user.c     # AF_XDP forwarder (zero-copy mode)
├── common.h          # Common definitions
├── deploy.sh         # Deployment script
├── test.sh           # Test script
└── Makefile          # Build file
```

### Key Files

| File | Description |
|------|-------------|
| `xdp_kern.c` | eBPF program that runs in kernel - does packet processing |
| `xdp_user.c` | Userspace controller - manages XDP program and flow table |
| `af_xdp_user.c` | AF_XDP implementation - zero-copy forwarding to userspace |
| `common.h` | Shared headers between kernel and userspace |
| `deploy.sh` | One-click deployment script |

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

### Quick Start

```bash
# Deploy XDP program
sudo ./deploy.sh deploy

# Or step by step
sudo ./deploy.sh build    # Build programs
sudo ./deploy.sh load     # Load XDP to interface
sudo ./deploy.sh start   # Start controller
```

### Manual Control

```bash
# Build XDP program
make

# Load XDP to interface (replace eth0 with your interface)
sudo ip link set eth0 xdp obj xdp_kern.o sec xdp

# Check XDP status
ip link show eth0

# Start controller (show statistics)
sudo ./xdp_user -s

# Start controller (show flow table)
sudo ./xdp_user -f

# Start controller (with AF_XDP mode)
sudo ./af_xdp_user -s
```

### Testing

```bash
# Run test suite
sudo ./test.sh all

# Individual tests
sudo ./test.sh loaded   # Check if XDP is loaded
sudo ./test.sh stats    # View XDP statistics
sudo ./test.sh mode     # Check XDP mode
sudo ./test.sh latency  # Latency test
```

## Configuration

### Adding Backend Servers

Edit `xdp_user.c` and modify the `backends` array:

```c
static struct backend backends[] = {
    { .ip = "192.168.1.10", .port = 8080 },
    { .ip = "192.168.1.11", .port = 8080 },
    { .ip = "192.168.1.12", .port = 8080 },
};
```

### Changing Load Balancing Algorithm

In `xdp_kern.c`, modify the `select_backend` function:

```c
// Round-robin (default)
backend_id = round_robin_index % num_backends;

// Source hash (consistent hashing)
backend_id = src_hash % num_backends;

// Random
backend_id = bpf_get_prandom_u32() % num_backends;
```

## Monitoring

### View Statistics

```bash
# Using xdp_user
sudo ./xdp_user -s

# Using ip command
ip -s link show eth0
```

### View Flow Table

```bash
# Show current connections
sudo ./xdp_user -f
```

### Debug XDP

```bash
# Check XDP logs
sudo cat /sys/kernel/debug/tracing/trace_pipe

# Set up debug buffer
sudo mount -t tracefs tracefs /sys/kernel/debug/tracing
```

## Requirements

- Linux kernel 5.4+ with XDP support
- clang and llvm
- libelf-dev
- iproute2

### Check XDP Support

```bash
# Check if your kernel supports XDP
ip link set eth0 xdp off
```

## Performance Tuning

1. **Huge Pages**
   ```bash
   sudo sysctl -w vm.nr_hugepages=1024
   ```

2. **Lock Memory**
   ```bash
   sudo ulimit -l unlimited
   ```

3. **CPU Affinity**
   ```bash
   sudo taskset -c 0 ./xdp_user
   ```

## License

GPL-2.0

## References

- [XDP Official Documentation](https://www.kernel.org/doc/Documentation/networking/filter.txt)
- [libbpf GitHub](https://github.com/libbpf/libbpf)
- [xdp-tools GitHub](https://github.com/xdp-project/xdp-tools)
- [BPF Performance Tools](http://www.brendangregg.com/bpfperformance.html)
