# Transport Services API Guide

This guide provides comprehensive documentation for using the Transport Services API, implementing the IETF Transport Services Architecture (RFC 9622) and API (RFC 9623).

## Table of Contents

1. [Introduction](#introduction)
2. [Core Concepts](#core-concepts)
3. [Quick Start](#quick-start)
4. [API Reference](#api-reference)
5. [Advanced Features](#advanced-features)
6. [Best Practices](#best-practices)
7. [Migration Guide](#migration-guide)

## Introduction

The Transport Services API provides a modern, protocol-independent interface for network communication. Instead of choosing between TCP, UDP, QUIC, or other protocols directly, applications express their communication requirements and the system automatically selects the best available protocol.

### Key Benefits

- **Protocol Independence**: Write once, run with any suitable protocol
- **Automatic Protocol Selection**: The system chooses the best protocol based on properties
- **Future-Proof**: New protocols are automatically used when available
- **Performance**: Features like 0-RTT, multipath, and connection groups
- **Security**: Built-in TLS with flexible callbacks

## Core Concepts

### 1. Preconnection

A `Preconnection` is a passive object that represents a potential connection. It holds:
- Endpoints (local and remote)
- Transport properties (requirements)
- Security parameters
- Message framers

```swift
let preconnection = Preconnection(
    remote: [RemoteEndpoint(kind: .host("example.com"))],
    transport: .reliableStream(),
    security: SecurityParameters()
)
```

### 2. Endpoints

Endpoints identify network locations:

```swift
// Remote endpoint (server address)
var remote = RemoteEndpoint(kind: .host("api.example.com"))
remote.port = 443

// Local endpoint (optional, for binding)
var local = LocalEndpoint(kind: .ip("0.0.0.0"))
local.port = 8080
```

### 3. Transport Properties

Properties express communication requirements using preferences:

```swift
var properties = TransportProperties()
properties.reliability = .require          // Must be reliable
properties.preserveMsgBoundaries = .prefer // Prefer message boundaries
properties.congestionControl = .require    // Must have congestion control
```

### 4. Connections

Active communication channels created from preconnections:

```swift
// Client connection
let connection = try await preconnection.initiate()

// Send data
try await connection.send(Message(data))

// Receive data
let message = try await connection.receive()

// Close gracefully
await connection.close()
```

## Quick Start

### Simple Client

```swift
import TransportServices

// 1. Create endpoint
var endpoint = RemoteEndpoint(kind: .host("example.com"))
endpoint.port = 443

// 2. Create preconnection
let preconnection = Preconnection(
    remote: [endpoint],
    transport: .reliableStream()
)

// 3. Connect
let connection = try await preconnection.initiate()

// 4. Use connection
let message = Message("Hello".data(using: .utf8)!)
try await connection.send(message)

let response = try await connection.receive()
print("Received: \(response.data)")

// 5. Close
await connection.close()
```

### Simple Server

```swift
// 1. Create local endpoint
var local = LocalEndpoint(kind: .ip("0.0.0.0"))
local.port = 8080

// 2. Create preconnection
let preconnection = Preconnection(
    local: [local],
    transport: .reliableStream()
)

// 3. Listen
let listener = try await preconnection.listen()

// 4. Accept connections
for try await connection in listener.newConnections {
    Task { await handleClient(connection) }
}
```

## API Reference

### Preconnection

#### Creating Preconnections

```swift
init(local: [LocalEndpoint] = [],
     remote: [RemoteEndpoint] = [],
     transport: TransportProperties = .init(),
     security: SecurityParameters = .init())
```

#### Connection Establishment

```swift
// Client - active open
func initiate(timeout: Duration? = nil) async throws -> Connection

// Client - with 0-RTT
func initiateWithSend(_ firstMessage: Message, 
                      timeout: Duration? = nil) async throws -> Connection

// Server - passive open
func listen() async throws -> Listener

// Peer-to-peer
func rendezvous() async throws -> Connection
```

#### Multicast

```swift
// Send to multicast group
func multicastSend(to endpoint: MulticastEndpoint) async throws -> Connection

// Receive from multicast group
func multicastReceive(from endpoint: MulticastEndpoint) async throws -> MulticastListener
```

### Connection

#### Data Transfer

```swift
// Send message
func send(_ message: Message) async throws

// Receive message
func receive() async throws -> Message

// Batch operations
func sendBatch(_ messages: [Message]) async throws
func receiveBatch(max: Int) async throws -> [Message]
```

#### Connection Management

```swift
// State
var state: ConnectionState { get }

// Endpoints
var localEndpoint: LocalEndpoint? { get }
var remoteEndpoint: RemoteEndpoint? { get }

// Lifecycle
func close() async  // Graceful close
func abort() async  // Immediate termination
```

#### Connection Groups

```swift
// Clone connection
func clone(framer: MessageFramer?, 
           altering: TransportProperties?) async throws -> Connection

// Group operations
func groupedConnections() async -> [Connection]
func closeGroup() async
func abortGroup() async
```

### Transport Properties

#### Pre-configured Profiles

```swift
// TCP-like (default)
TransportProperties.reliableStream()

// UDP-like
TransportProperties.unreliableDatagram()

// SCTP-like
TransportProperties.reliableMessage()

// Optimized profiles
TransportProperties.lowLatency()      // Gaming, video calls
TransportProperties.bulkData()        // File transfer
TransportProperties.mediaStream()     // Live streaming
TransportProperties.privacyEnhanced() // Maximum privacy
```

#### Custom Configuration

```swift
var properties = TransportProperties()

// Reliability
properties.reliability = .require
properties.preserveOrder = .require
properties.perMsgReliability = .prefer

// Performance
properties.zeroRTT = .prefer
properties.multipathMode = .active
properties.congestionControl = .require

// Privacy
properties.useTemporaryAddress = .require
properties.advertisesAltAddr = false
```

### Security

#### Security Parameters

```swift
var security = SecurityParameters()

// Protocol versions
security.allowedProtocols = ["TLS 1.3", "TLS 1.2"]

// Certificates
security.localIdentity = loadClientCertificate()
security.trustedCAs = loadTrustedRoots()
```

#### Security Callbacks

```swift
// Custom trust verification
security.callbacks.trustVerificationCallback = { context in
    // Inspect certificates
    for cert in context.certificateChain {
        print("Subject: \(cert.subject)")
        print("Issuer: \(cert.issuer)")
    }
    
    // Make decision
    if isPinned(context.certificateChain.first) {
        return .accept
    }
    return .reject
}

// Client certificate selection
security.callbacks.identityChallengeCallback = { context in
    let (cert, key) = selectClientCertificate(
        acceptableIssuers: context.acceptableIssuers
    )
    
    return IdentityChallengeResult(
        certificate: cert,
        privateKey: key
    )
}
```

## Advanced Features

### 1. Rendezvous (Peer-to-Peer)

```swift
// Configure STUN for NAT traversal
var stunEndpoint = LocalEndpoint(kind: .host("stun.example.com"))
stunEndpoint.port = 3478

let preconnection = Preconnection(
    local: [stunEndpoint],
    transport: .lowLatency()
)

// Gather candidates
let (locals, _) = try await preconnection.resolve()

// Exchange via signaling
sendCandidates(locals)
let remotes = receiveCandidates()

// Add remote candidates
for remote in remotes {
    await preconnection.add(remote: remote)
}

// Connect
let connection = try await preconnection.rendezvous()
```

### 2. Connection Groups

```swift
// Create primary connection
let primary = try await preconnection.initiate()

// Clone for data streams
let dataStream1 = try await primary.clone()
let dataStream2 = try await primary.clone()

// High-priority control stream
var controlProps = TransportProperties()
// Set priority
let control = try await primary.clone(altering: controlProps)

// Use all streams concurrently
async let d1 = dataStream1.send(data1)
async let d2 = dataStream2.send(data2)
async let c = control.send(command)

_ = await (d1, d2, c)

// Close all at once
await primary.closeGroup()
```

### 3. Multicast

```swift
// ASM (Any-Source Multicast)
let asmEndpoint = MulticastEndpoint(
    groupAddress: "239.1.1.1",
    port: 5353,
    ttl: 1
)

// SSM (Source-Specific Multicast)
let ssmEndpoint = MulticastEndpoint(
    groupAddress: "232.1.1.1",
    sources: ["192.168.1.100"],
    port: 5353
)

// Send
let sender = try await preconnection.multicastSend(to: endpoint)

// Receive
let listener = try await preconnection.multicastReceive(from: endpoint)
for try await connection in listener.newConnections {
    // Handle each unique sender
}
```

### 4. 0-RTT (Zero Round-Trip Time)

```swift
// Mark message as safely replayable
var message = Message(data)
message.context.safelyReplayable = true

// Configure for 0-RTT
var properties = TransportProperties()
properties.zeroRTT = .prefer

// Connect and send in one operation
let connection = try await preconnection.initiateWithSend(message)
```

## Best Practices

### 1. Property Selection

```swift
// DO: Express actual requirements
properties.reliability = .require      // Need reliable delivery
properties.preserveOrder = .noPreference // Don't care about order

// DON'T: Over-constrain
properties.reliability = .require
properties.preserveOrder = .require     // Unnecessary constraint
properties.congestionControl = .require // Limits protocol selection
```

### 2. Error Handling

```swift
do {
    let connection = try await preconnection.initiate()
    // Use connection
} catch TransportError.establishmentFailure(let reason) {
    // Handle connection failure
    print("Failed to connect: \(reason)")
} catch TransportError.sendFailure(let reason) {
    // Handle send failure
    print("Failed to send: \(reason)")
}
```

### 3. Connection Lifecycle

```swift
// Always close connections
defer {
    Task { await connection.close() }
}

// Use connection groups for related streams
let primary = try await preconnection.initiate()
defer {
    Task { await primary.closeGroup() } // Closes all cloned connections
}
```

### 4. Security

```swift
// Always validate certificates in production
security.callbacks.trustVerificationCallback = { context in
    // Never blindly accept
    guard validateCertificateChain(context.certificateChain) else {
        return .reject
    }
    return .accept
}

// Use 0-RTT carefully
if message.isSafeToReplay {
    message.context.safelyReplayable = true
    // Use initiateWithSend
} else {
    // Use regular initiate
}
```

## Migration Guide

### From BSD Sockets

```swift
// Before (BSD sockets)
let socket = socket(AF_INET, SOCK_STREAM, 0)
connect(socket, &addr, socklen_t(MemoryLayout.size(ofValue: addr)))
send(socket, data, data.count, 0)

// After (Transport Services)
let connection = try await preconnection.initiate()
try await connection.send(Message(data))
```

### From URLSession

```swift
// Before (URLSession)
let task = URLSession.shared.dataTask(with: url) { data, response, error in
    // Handle response
}
task.resume()

// After (Transport Services)
let connection = try await preconnection.initiate()
try await connection.send(httpRequest)
let response = try await connection.receive()
```

### From Network.framework

```swift
// Before (Network.framework)
let connection = NWConnection(
    host: "example.com",
    port: 443,
    using: .tcp
)

// After (Transport Services)
let connection = try await Preconnection(
    remote: [RemoteEndpoint(kind: .host("example.com"))],
    transport: .reliableStream()
).initiate()
```

## Troubleshooting

### Common Issues

1. **Connection Fails**
   - Check endpoint configuration
   - Verify network connectivity
   - Review transport properties for conflicts

2. **0-RTT Rejected**
   - Ensure message is marked as safely replayable
   - Server may not support 0-RTT
   - Fall back to regular connection

3. **Multicast Not Working**
   - Verify multicast address range (224.0.0.0/4 or ff00::/8)
   - Check TTL settings
   - Ensure network supports multicast

4. **Performance Issues**
   - Use connection groups for multiple streams
   - Enable multipath if available
   - Consider 0-RTT for latency-sensitive operations

### Debug Logging

```swift
// Enable debug output
var properties = TransportProperties()
// Implementation-specific debug flags
```

## Further Reading

- [RFC 9622](https://www.rfc-editor.org/rfc/rfc9622.html) - Transport Services Architecture
- [RFC 9623](https://www.rfc-editor.org/rfc/rfc9623.html) - Transport Services API
- [Examples Directory](Examples/) - Complete working examples
- [API Reference](Sources/TransportServices/) - Source documentation