#!/bin/bash

# Accept optional filter as first argument
FILTER="${1:-}"

# Build the swift test command with optional filter
if [ -n "$FILTER" ]; then
    CMD="swift test --filter $FILTER"
else
    CMD="swift test"
fi

# Run tests with timeout
timeout 15s $CMD
EXIT_CODE=$?

# Handle timeout
if [ $EXIT_CODE -eq 124 ]; then
    echo "Error: test hung longer than 15 seconds"
    
    # Find and kill any Swift test processes
    # Look for processes that contain both "swift" and "test"
    pids=$(ps aux | grep -E "swift.*test|test.*swift" | grep -v grep | grep -v ".run-tests.sh" | awk '{print $2}')
    if [ -n "$pids" ]; then
        echo "Killing Swift test processes: $pids"
        kill $pids 2>/dev/null
        sleep 1
        # Force kill if still running
        remaining=$(ps aux | grep -E "swift.*test|test.*swift" | grep -v grep | grep -v ".run-tests.sh" | awk '{print $2}')
        if [ -n "$remaining" ]; then
            kill -9 $remaining 2>/dev/null
        fi
    fi
    
    # Also look for any SwiftPM process using our build directory
    swiftpm_pids=$(ps aux | grep -F ".build" | grep -i swift | grep -v grep | awk '{print $2}')
    if [ -n "$swiftpm_pids" ]; then
        echo "Killing SwiftPM processes using .build: $swiftpm_pids"
        kill $swiftpm_pids 2>/dev/null
    fi
    
    exit 124
fi

# Exit with the original exit code
exit $EXIT_CODE
