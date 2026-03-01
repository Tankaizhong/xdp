#!/bin/bash
# Simple network topology test for XDP Load Balancer
# This verifies the network setup works; full XDP test requires actual XDP loading

set -e

cleanup() {
    for ns in ns-client ns-lb ns-backend1 ns-backend2 ns-backend3; do
        ip netns del $ns 2>/dev/null || true
    done
    for veth in veth-c-l veth-l-c veth-l-b1 veth-l-b2 veth-l-b3 veth-b1-l veth-b2-l veth-b3-l; do
        ip link del $veth 2>/dev/null || true
    done
}

cleanup

echo "=== Creating Network Topology ==="

# Create namespaces
for ns in ns-client ns-lb ns-backend1 ns-backend2 ns-backend3; do
    ip netns add $ns
done

# Create veth pairs: client <-> lb
ip link add veth-c-l type veth peer name veth-l-c
ip link set veth-c-l netns ns-client
ip link set veth-l-c netns ns-lb

# Create veth pairs: lb <-> backends
ip link add veth-l-b1 type veth peer name veth-b1-l
ip link set veth-l-b1 netns ns-lb
ip link set veth-b1-l netns ns-backend1

ip link add veth-l-b2 type veth peer name veth-b2-l
ip link set veth-l-b2 netns ns-lb
ip link set veth-b2-l netns ns-backend2

ip link add veth-l-b3 type veth peer name veth-b3-l
ip link set veth-l-b3 netns ns-lb
ip link set veth-b3-l netns ns-backend3

echo "=== Configuring IPs ==="

# LB: VIP (frontend) + backend interface
ip netns exec ns-lb ip addr add 192.168.88.10/24 dev veth-l-c
ip netns exec ns-lb ip addr add 192.168.89.10/24 dev veth-l-b1
ip netns exec ns-lb ip link set veth-l-c up
ip netns exec ns-lb ip link set veth-l-b1 up
ip netns exec ns-lb ip link set veth-l-b2 up
ip netns exec ns-lb ip link set veth-l-b3 up
ip netns exec ns-lb ip link set lo up

# Client
ip netns exec ns-client ip addr add 192.168.88.100/24 dev veth-c-l
ip netns exec ns-client ip link set veth-c-l up
ip netns exec ns-client ip route add 192.168.89.0/24 via 192.168.88.10

# Backends
ip netns exec ns-backend1 ip addr add 192.168.89.101/24 dev veth-b1-l
ip netns exec ns-backend1 ip link set veth-b1-l up
ip netns exec ns-backend1 ip link set lo up

ip netns exec ns-backend2 ip addr add 192.168.89.102/24 dev veth-b2-l
ip netns exec ns-backend2 ip link set veth-b2-l up
ip netns exec ns-backend2 ip link set lo up

ip netns exec ns-backend3 ip addr add 192.168.89.103/24 dev veth-b3-l
ip netns exec ns-backend3 ip link set veth-b3-l up
ip netns exec ns-backend3 ip link set lo up

echo "=== Testing Connectivity ==="

echo -n "Client -> VIP: "
ip netns exec ns-client ping -c 1 -W 1 192.168.88.10 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "VIP -> Backend1: "
ip netns exec ns-lb ping -c 1 -W 1 192.168.89.101 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "VIP -> Backend2: "
ip netns exec ns-lb ping -c 1 -W 1 192.168.89.102 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "VIP -> Backend3: "
ip netns exec ns-lb ping -c 1 -W 1 192.168.89.103 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "Client -> Backend1 (via LB): "
ip netns exec ns-client ping -c 1 -W 1 192.168.89.101 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo ""
echo "=== Network Topology Ready ==="
echo "To test XDP load balancer:"
echo "1. Load XDP program on LB namespace (requires XDP-supported interface)"
echo "2. Start HTTP servers on backends"
echo "3. Send requests to VIP: curl http://192.168.88.10:8080"
echo ""
echo "Cleanup..."
cleanup
echo "Done!"
