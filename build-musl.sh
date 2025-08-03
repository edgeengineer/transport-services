#!/bin/bash
# Build script for Musl libc (Alpine Linux)

set -e

echo "Building TAPS-Swift with Musl libc support..."

# Detect the operating system
OS=$(uname -s)
ARCH=$(uname -m)

if [ "$OS" = "Darwin" ]; then
    echo "Running on macOS - building without static linking"
    echo "To build with Musl, use Docker:"
    echo "  docker build -f Dockerfile.alpine -t taps-swift-musl ."
    echo "  docker run -it taps-swift-musl"
    echo ""
    echo "Building for macOS..."
    
    # Build for macOS without static linking
    swift build -c release -Xswiftc -DMUSL_LIBC
    
elif [ -f /etc/alpine-release ]; then
    echo "Detected Alpine Linux with Musl libc"
    echo "Building static binary..."
    
    # Build with optimizations for Musl on Alpine
    swift build \
        -c release \
        -Xswiftc -DMUSL_LIBC \
        -Xswiftc -static-stdlib \
        -Xlinker -static
        
elif [ "$OS" = "Linux" ]; then
    echo "Detected Linux (non-Alpine)"
    
    # Check for musl
    if ldd --version 2>&1 | grep -q musl; then
        echo "Musl libc detected"
        # Build with static linking for Musl
        swift build \
            -c release \
            -Xswiftc -DMUSL_LIBC \
            -Xswiftc -static-stdlib \
            -Xlinker -static
    else
        echo "Glibc detected - building without full static linking"
        # Build for Glibc without full static linking
        swift build -c release
    fi
else
    echo "Unknown platform: $OS"
    exit 1
fi

echo "Build complete!"

# Run tests if requested
if [ "$1" == "--test" ]; then
    echo "Running tests..."
    swift test
fi