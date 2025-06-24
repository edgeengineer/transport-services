# Transport Services Examples

This directory contains practical examples demonstrating how to use the Transport Services API for various networking scenarios.

## Examples Overview

### Basic Examples

1. **SimpleClient.swift** - Basic TCP-like client connection
2. **SimpleServer.swift** - Basic TCP-like server listener
3. **UDPExample.swift** - Unreliable datagram communication

### Advanced Examples

4. **RendezvousExample.swift** - Peer-to-peer connection with NAT traversal
5. **ConnectionGroupExample.swift** - Managing multiple related connections
6. **MulticastExample.swift** - Multicast sender and receiver
7. **ZeroRTTExample.swift** - 0-RTT connection establishment
8. **SecurityCallbackExample.swift** - Custom certificate validation

### Use Case Examples

9. **ChatApplication.swift** - Simple chat using reliable messages
10. **FileTransfer.swift** - Bulk data transfer with progress
11. **VideoStreaming.swift** - Real-time media streaming
12. **GameNetworking.swift** - Low-latency game networking

## Running the Examples

Each example is a standalone Swift file that can be run with:

```bash
swift run ExampleName
```

Make sure you have built the Transport Services package first:

```bash
swift build
```

## Key Concepts Demonstrated

- **Protocol Selection**: How Transport Services automatically selects the best protocol
- **Property Configuration**: Using pre-configured profiles and custom properties
- **Error Handling**: Proper handling of network errors and edge cases
- **Performance Optimization**: Using features like 0-RTT and multipath
- **Security**: Implementing custom security callbacks and policies