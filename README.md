# Transport Services

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20Linux-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![macOS](https://img.shields.io/github/actions/workflow/status/edgeengineer/transport-services/swift.yml?branch=main&label=macOS)](https://github.com/edgeengineer/transport-services/actions/workflows/swift.yml)
[![Linux](https://img.shields.io/github/actions/workflow/status/edgeengineer/transport-services/swift.yml?branch=main&label=Linux)](https://github.com/edgeengineer/transport-services/actions/workflows/swift.yml)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://edgeengineer.github.io/transport-services/documentation/transportservices/)

`TransportServices` is a modern, protocol-agnostic networking framework for Swift, built on the principles of the IETF Transport Services (TAPS) architecture. It provides a high-level, asynchronous, and message-oriented API that allows applications to express their networking *intent* rather than being hard-coded to a specific transport protocol like TCP or UDP.

## Motivation: Evolving the Network API

Traditional networking APIs, like Berkeley Sockets, tightly couple applications to specific transport protocols. This legacy model presents several challenges in today's rapidly evolving internet:

-   **Protocol Rigidity:** Applications must be manually updated to support new protocols like QUIC or SCTP.
-   **Path Agility:** They cannot easily take advantage of multiple network interfaces (e.g., Wi-Fi and Cellular) simultaneously for better performance and reliability.
-   **Repetitive Logic:** Common patterns like "Happy Eyeballs" (racing IPv4 and IPv6) must be re-implemented in every application.

As outlined in the **TAPS Architecture ([`spec/rfc9621.txt`](spec/rfc9621.txt))**, the goal of this library is to solve these problems by providing an abstraction layer. The `TransportServices` implementation can dynamically select the best protocol and network path based on application requirements and network conditions, enabling faster, more reliable, and more resilient networking without requiring application changes.

## Core Concepts

This library implements the abstract API defined in **[`spec/rfc9622.txt`](spec/rfc9622.txt)**, centered around these key concepts:

-   **Preconnection:** An object for specifying your networking requirements *before* a connection is established. You define what you need (reliability, ordering, low latency) rather than picking a protocol.
-   **Connection:** A unified, protocol-agnostic object representing a communication channel. Once established, you `send()` and `receive()` messages regardless of whether the underlying transport is TCP, QUIC, or UDP.
-   **Listener:** An object for accepting incoming connections, which creates new `Connection` objects as peers connect.
-   **Asynchronous, Event-Driven API:** All network operations are non-blocking and communicate their results through events, fitting naturally into modern Swift concurrency.
-   **Message-Oriented Data Transfer:** Data is sent and received as discrete `Message` objects, which aligns better with application logic than raw byte streams.
-   **Protocol & Path Agility:** The framework handles the complexity of choosing between protocols (e.g., TCP, UDP), racing connections (e.g., "Happy Eyeballs"), and migrating between network paths.
-   **Extensible Security:** Integrates transport security (like TLS) as a first-class feature.

## Table of Contents

- [Motivation](#motivation-evolving-the-network-api)
- [Core Concepts](#core-concepts)
- [Installation](#installation)
- [Quick Start](#quick-start)
  - [Client Example: Connecting to a Service](#1-client-example-connecting-to-a-service)
  - [Server Example: Listening for Connections](#2-server-example-listening-for-connections)
- [Documentation](#documentation)
- [Advanced Usage](#advanced-usage)
- [License](#license)

## Installation

### Swift Package Manager

Add the `TransportServices` package to your `Package.swift` dependencies:

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "YourProject",
    dependencies: [
        .package(url: "https://github.com/edgeengineer/transport-services", from: "0.0.2")
    ],
    targets: [
        .target(
            name: "YourTarget",
            dependencies: [
                .product(name: "TransportServices", package: "transport-services")
            ]
        )
    ]
)
```

## Quick Start

### 1. Client Example: Connecting to a Service

This example shows how to connect to an echo service. The application requests a reliable transport but does not need to know if it's TCP or another protocol.

```swift
import TransportServices

// 1. Specify the remote endpoint
let remoteEndpoint = RemoteEndpoint(host: "echo.example.com", port: 7)

// 2. Define transport properties. We need reliability.
var properties = TransportProperties()
properties.reliability = .require

// 3. Create a Preconnection with our endpoint and properties.
//    No security is needed for this simple example.
let preconnection = Preconnection(remote: remoteEndpoint,
                                  properties: properties,
                                  security: .disabled)

// 4. Initiate the connection
let connection = try await preconnection.initiate()

Task {
    // Listen for events on the connection
    for await event in connection.events {
        switch event {
        case .ready:
            print("Connection is ready. Sending 'Hello'.")
            let message = Message("Hello, TAPS!".data(using: .utf8)!)
            try await connection.send(message)
        case .received(let message):
            let response = String(data: message.data, encoding: .utf8) ?? "Invalid UTF-8"
            print("Received response: \(response)")
            await connection.close() // We are done, close the connection
        case .closed:
            print("Connection closed.")
            return // End the task
        case .error(let error):
            print("Connection error: \(error)")
            return // End the task
        default:
            break
        }
    }
}
```

### 2. Server Example: Listening for Connections

This example shows how to create a simple server that listens for incoming connections and echoes back any messages it receives.

```swift
import TransportServices

// 1. Specify the local endpoint to listen on.
//    Listen on all interfaces on port 1234.
let localEndpoint = LocalEndpoint(port: 1234)

// 2. Define transport properties. We require reliability.
var properties = TransportProperties()
properties.reliability = .require

// 3. Create a Preconnection.
let preconnection = Preconnection(local: localEndpoint,
                                  properties: properties,
                                  security: .disabled)

// 4. Start listening for incoming connections.
let listener = try await preconnection.listen()
print("Server listening on port 1234...")

// 5. Accept new connections in a loop.
for await newConnection in listener.connections {
    print("Accepted a new connection from \(newConnection.remoteEndpoint?.host ?? "unknown")")
    
    // Handle each connection concurrently in its own Task.
    Task {
        for await event in newConnection.events {
            if case .received(let message) = event {
                let receivedText = String(data: message.data, encoding: .utf8) ?? ""
                print("Received '\(receivedText)', echoing back.")
                // Echo the message back to the client.
                try await newConnection.send(message)
            }
        }
    }
}
```

## Documentation

### 📚 [API Guide](API_GUIDE.md)

Comprehensive guide covering:
- Core concepts and architecture
- Complete API reference
- Advanced features (Rendezvous, Connection Groups, Multicast, 0-RTT)
- Best practices and performance tips
- Migration guides from BSD sockets, URLSession, and Network.framework

### 🧪 [Examples](Examples/README.md)

Practical, runnable examples demonstrating:
- Basic client/server connections
- Peer-to-peer with NAT traversal
- Connection groups and multistreaming
- Multicast communication
- Custom security callbacks
- 0-RTT optimization techniques

## Advanced Usage

The `TransportServices` framework is designed to support advanced networking scenarios. The full implementation will include:

-   **Peer-to-Peer (`Rendezvous`):** Establishing direct connections between clients, potentially using STUN/ICE for NAT traversal (RFC 9622, Section 7.3).
-   **Connection Groups (`Clone`):** Managing multiple streams within a single transport session, ideal for protocols like QUIC and HTTP/2 (RFC 9622, Section 7.4).
-   **Multicast:** Joining multicast groups for efficient one-to-many communication (RFC 9622, Section 6.1.1).
-   **Custom Security:** Providing fine-grained control over TLS parameters and trust evaluation.

For a detailed roadmap of planned features, please see the `IMPROVEMENTS.md` file.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.