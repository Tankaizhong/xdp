#!/bin/bash
# Test script for XDP Load Balancer - Network Namespace Simulation

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== XDP Load Balancer Test ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

cleanup() {
    echo -e "${YELLOW}[Cleanup] Removing network namespaces...${NC}"
    for ns in client lb backend1 backend2 backend3; do
        ip netns del $ns 2>/dev/null || true
    done
    for veth in veth0 veth1 veth2 veth3 veth4; do
        ip link del $veth 2>/dev/null || true
    done
}

# Cleanup first
cleanup

echo -e "${GREEN}[1] Creating network namespaces...${NC}"
ip netns add client
ip netns add lb
ip netns add backend1
ip netns add backend2
ip netns add backend3

echo -e "${GREEN}[2] Creating veth pairs...${NC}"
ip link add veth0 type veth peer name veth0h
ip link add veth1 type veth peer name veth1h
ip link add veth2 type veth peer name veth2h
ip link add veth3 type veth peer name veth3h
ip link add veth4 type veth peer name veth4h

# Move veths to namespaces
ip link set veth0h netns lb
ip link set veth1h netns lb

ip link set veth0 netns client

ip link set veth1h netns backend1
ip link set veth2h netns backend2
ip link set veth3h netns backend3

echo -e "${GREEN}[3] Configuring network...${NC}"

# LB namespace - Frontend (VIP) and Backend interface
ip netns exec lb ip addr add 192.168.88.10/24 dev veth0h
ip netns exec lb ip addr add 192.168.89.10/24 dev veth1h
ip netns exec lb ip link set veth0h up
ip netns exec lb ip link set veth1h up
ip netns exec lb ip link set lo up

# Client namespace
ip netns exec client ip addr add 192.168.88.100/24 dev veth0
ip netns exec client ip link set veth0 up
ip netns exec client ip route add 192.168.89.0/24 via 192.168.88.10

# Backend namespaces
ip netns exec backend1 ip addr add 192.168.89.101/24 dev veth1h
ip netns exec backend1 ip link set veth1h up
ip netns exec backend1 ip link set lo up

ip netns exec backend2 ip addr add 192.168.89.102/24 dev veth2h
ip netns exec backend2 ip link set veth2h up
ip netns exec backend2 ip link set lo up

ip netns exec backend3 ip addr add 192.168.89.103/24 dev veth3h
ip netns exec backend3 ip link set veth3h up
ip netns exec backend3 ip link set lo up

echo -e "${GREEN}[4] Starting HTTP servers on backends...${NC}"
for i in 1 2 3; do
    ip netns exec backend$i sh -c "echo 'Backend $i' | nc -l -p 8080 >/dev/null 2>&1 &"
done
sleep 1

echo -e "${GREEN}[5] Running load test...${NC}"
echo "Sending 20 requests to 192.168.88.10:8080"
echo ""

# Results tracking
declare -A results
for i in {1..20}; do
    result=$(ip netns exec client timeout 1s curl -s http://192.168.88.10:8080 2>/dev/null || echo "FAILED")
    if [[ "$result" == "FAILED" ]]; then
        echo "Request $i: ${RED}FAILED${NC}"
    else
        echo "Request $i: ${GREEN}$result${NC}"
        results[$result]=$((${results[$result]:-0} + 1))
    fi
done

echo ""
echo "=== Load Balancing Results ==="
for backend in "Backend 1" "Backend 2" "Backend 3"; do
    count=${results[$backend]:-0}
    echo "$backend: $count requests"
done

echo ""
echo -e "${YELLOW}[6] Cleanup${NC}"
cleanup

echo ""
echo "=== Test Complete ==="
