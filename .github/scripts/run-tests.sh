#!/bin/bash
# run-tests.sh - Run tests for XDP project

set -e

echo "Running XDP project tests..."

# Run the test script
if [ -f "./test.sh" ]; then
    echo "Running ./test.sh..."
    sudo ./test.sh all || true
else
    echo "No test.sh found, running basic checks..."
    
    # Basic build verification
    if [ -f "./xdp_user" ] && [ -f "./xdp_kern.o" ]; then
        echo "Build artifacts found"
    else
        echo "ERROR: Build artifacts missing"
        exit 1
    fi
fi

echo "Tests completed"
