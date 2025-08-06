# TransportServices: A Cross-Platform Transport Services Implementation

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20Linux%20|%20Windows%20|%20Android-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![macOS](https://img.shields.io/github/actions/workflow/status/edgeengineer/transport-services/swift.yml?branch=main&label=macOS)](https://github.com/edgeengineer/transport-services/actions/workflows/swift.yml)
[![Linux](https://img.shields.io/github/actions/workflow/status/edgeengineer/transport-services/swift.yml?branch=main&label=Linux)](https://github.com/edgeengineer/transport-services/actions/workflows/swift.yml)
[![Windows](https://img.shields.io/github/actions/workflow/status/edgeengineer/transport-services/swift.yml?branch=main&label=Windows)](https://github.com/edgeengineer/transport-services/actions/workflows/swift.yml)

`TransportServices` is a modern, cross-platform networking library for Swift, providing an implementation of the Transport Services (TAPS) system defined by the IETF.

The traditional Socket API forces applications to bind directly to specific transport protocols like TCP or UDP. As described in the [Transport Services Architecture (RFC 9621)](spec/rfc9621.txt), this model hinders the evolution and deployment of new transport protocols. Applications become locked into a single transport, unable to adapt to changing network conditions or take advantage of newer, more efficient protocols without significant code changes.

The TAPS architecture solves this by introducing a protocol-agnostic, abstract API. Instead of requesting a specific protocol, an application specifies its requirements—such as reliability, ordering, and message boundary preservation. The TAPS implementation then dynamically selects the optimal protocol and network path to satisfy those requirements. This allows applications to seamlessly benefit from transport innovations like QUIC, Multipath TCP, and others without modification.

This library brings the power and flexibility of the TAPS architecture to the Swift ecosystem, targeting Swift 6 and beyond.

## Installation

You can add `TransportServices` to your project using Swift Package Manager. Add the following to your `Package.swift` file's dependencies:

```swift
.package(url: "https://github.com/edgeengineer/transport-services.git", from: "1.0.0")
```

And add it to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "TransportServices", package: "transport-services"),
    ]
),
```

## Quick Start

Here are some basic examples of how to use `TransportServices`.

### Client Example

This example shows how to create a client that connects to a server, sends a message, and receives a response.

```swift
import TransportServices
import Foundation

// 1. Define the remote endpoint
var remoteEndpoint = RemoteEndpoint()
remoteEndpoint.hostName = "example.com"
remoteEndpoint.port = 443

// 2. Create a Preconnection
// By default, this requests a reliable, ordered connection (like TCP).
let preconnection = NewPreconnection(remoteEndpoints: [remoteEndpoint])

// 3. Initiate the connection
// The event handler will receive all connection events.
let connection = try await preconnection.initiate { event in
    switch event {
    case .ready(let connection):
        print("Connection is ready.")
        // Now we can send data
        Task {
            do {
                let message = "Hello, Server!".data(using: .utf8)!
                try await connection.send(data: message)
                print("Sent message.")

                // Wait for a response
                let (responseData, _) = try await connection.receive()
                if let responseString = String(data: responseData, encoding: .utf8) {
                    print("Received response: \(responseString)")
                }
                
                // Close the connection
                await connection.close()

            } catch {
                print("An error occurred: \(error)")
                await connection.abort()
            }
        }
    case .closed(_):
        print("Connection closed.")
    case .connectionError(_, let reason):
        print("Connection error: \(reason ?? "Unknown")")
    default:
        // Handle other events like sent, received, etc.
        break
    }
}
```

### Server Example

This example shows how to create a server that listens for incoming connections.

```swift
import TransportServices
import Foundation

// 1. Define the local endpoint to listen on
var localEndpoint = LocalEndpoint()
localEndpoint.port = 8080

// 2. Create a Preconnection for the listener
let preconnection = NewPreconnection(localEndpoints: [localEndpoint])

// 3. Start listening for connections
let listener = try await preconnection.listen { event in
    switch event {
    case .connectionReceived(let listener, let newConnection):
        print("Accepted a new connection.")
        
        // Handle the new connection
        Task {
            do {
                // Receive data from the client
                let (receivedData, _) = try await newConnection.receive()
                if let message = String(data: receivedData, encoding: .utf8) {
                    print("Received from client: \(message)")
                }

                // Send a response back
                let response = "Hello, Client!".data(using: .utf8)!
                try await newConnection.send(data: response)
                
                // Close the client connection
                await newConnection.close()

            } catch {
                print("Error handling connection: \(error)")
                await newConnection.abort()
            }
        }
    case .stopped(_):
        print("Listener stopped.")
    case .listenerError(_, let reason):
        print("Listener error: \(reason ?? "Unknown")")
    default:
        break
    }
}

print("Server listening on port 8080...")

// To stop the listener after some time:
// try await Task.sleep(nanoseconds: 60_000_000_000)
// await listener.stop()

```

## Features

*   An implementation of the abstract Transport Services API defined in [RFC 9622](spec/rfc9622.txt).
*   Asynchronous, event-driven networking model.
*   Dynamic selection of transport protocols and network paths based on application-defined properties.
*   A unified interface for stream-oriented, message-oriented, and datagram-based communication.

## Requirements

*   Swift 6 or higher

## Roadmap

We are continuously working to expand the capabilities of this library. Future work includes:
*   Adding QUIC support for Linux and Windows.
*   Implementing L2CAP Connections for direct communication over Bluetooth.

## Related RFCs

The development of this library is guided by the TAPS working group specifications. You can find the relevant documents in the [`spec/`](spec/) directory.
*   [RFC 9621: Architecture and Requirements for Transport Services](spec/rfc9621.txt)
*   [RFC 9622: An Abstract Application Programming Interface (API) for Transport Services](spec/rfc9622.txt)
*   [RFC 9623: Implementing Interfaces to Transport Services](spec/rfc9623.txt)

## License

This project is licensed under the MIT License.

**MIT License**

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.