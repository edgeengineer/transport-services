#!/usr/bin/env swift

import TransportServices
import Foundation

/// Multicast Example
///
/// This example demonstrates:
/// - Creating multicast senders and receivers
/// - Joining multicast groups
/// - Handling multiple senders in a group
/// - Both ASM and SSM multicast

@main
struct MulticastExample {
    static func main() async {
        // Run sender and receiver concurrently
        async let sender = runMulticastSender()
        async let receiver = runMulticastReceiver()
        
        let _ = await (sender, receiver)
    }
    
    // MARK: - Multicast Sender
    
    static func runMulticastSender() async {
        do {
            print("[Sender] Starting multicast sender...")
            
            // Create multicast endpoint for sending
            let multicastEndpoint = MulticastEndpoint(
                groupAddress: "239.1.1.1",  // Private multicast range
                port: 5353,
                ttl: 1,  // Local network only
                loopback: true  // Receive our own messages for testing
            )
            
            // Create sender connection
            let preconnection = Preconnection()
            let sender = try await preconnection.multicastSend(to: multicastEndpoint)
            
            print("[Sender] Joined multicast group \(multicastEndpoint.groupAddress)")
            
            // Send messages periodically
            for i in 1...5 {
                let message = Message("Multicast message \(i)".data(using: .utf8)!)
                try await sender.send(message)
                print("[Sender] Sent message \(i)")
                
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
            await sender.close()
            print("[Sender] Multicast sender closed")
            
        } catch {
            print("[Sender] Error: \(error)")
        }
    }
    
    // MARK: - Multicast Receiver
    
    static func runMulticastReceiver() async {
        do {
            print("[Receiver] Starting multicast receiver...")
            
            // Create multicast endpoint for receiving
            let multicastEndpoint = MulticastEndpoint(
                groupAddress: "239.1.1.1",
                port: 5353
            )
            
            // Create receiver listener
            let preconnection = Preconnection()
            let listener = try await preconnection.multicastReceive(from: multicastEndpoint)
            
            print("[Receiver] Listening on multicast group \(multicastEndpoint.groupAddress)")
            
            // Handle connections from different senders
            Task {
                for try await connection in await listener.newConnections {
                    Task {
                        await handleMulticastSender(connection)
                    }
                }
            }
            
            // Keep receiver running
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            
            await listener.stop()
            print("[Receiver] Multicast receiver stopped")
            
        } catch {
            print("[Receiver] Error: \(error)")
        }
    }
    
    static func handleMulticastSender(_ connection: Connection) async {
        do {
            print("[Receiver] New sender detected")
            
            while true {
                let message = try await connection.receive()
                if let text = String(data: message.data, encoding: .utf8) {
                    print("[Receiver] Received: \(text)")
                }
            }
        } catch {
            print("[Receiver] Sender disconnected: \(error)")
        }
    }
}

// Source-Specific Multicast (SSM) Example:
/*
class SSMReceiver {
    func joinSSMGroup() async throws {
        // Create SSM endpoint with specific sources
        let ssmEndpoint = MulticastEndpoint(
            groupAddress: "232.1.1.1",  // SSM range
            sources: ["192.168.1.100", "192.168.1.101"],  // Allowed senders
            port: 5354
        )
        
        let preconnection = Preconnection()
        let listener = try await preconnection.multicastReceive(from: ssmEndpoint)
        
        // Only receives from specified sources
        for try await connection in await listener.newConnections {
            // Handle authorized sender
        }
    }
}

// Multicast Service Discovery Example:
class ServiceDiscovery {
    private let serviceGroup = "239.255.255.250"  // mDNS group
    private let servicePort: UInt16 = 5353
    
    func advertiseService(name: String, port: UInt16) async throws {
        let endpoint = MulticastEndpoint(
            groupAddress: serviceGroup,
            port: servicePort,
            ttl: 255  // Site-wide
        )
        
        let preconnection = Preconnection()
        let sender = try await preconnection.multicastSend(to: endpoint)
        
        // Send service announcement
        let announcement = """
        SERVICE: \(name)
        PORT: \(port)
        """
        
        let message = Message(announcement.data(using: .utf8)!)
        try await sender.send(message)
    }
    
    func discoverServices() async throws -> AsyncStream<(String, UInt16)> {
        let endpoint = MulticastEndpoint(
            groupAddress: serviceGroup,
            port: servicePort
        )
        
        let preconnection = Preconnection()
        let listener = try await preconnection.multicastReceive(from: endpoint)
        
        return AsyncStream { continuation in
            Task {
                for try await connection in await listener.newConnections {
                    Task {
                        do {
                            let message = try await connection.receive()
                            // Parse service announcement
                            if let text = String(data: message.data, encoding: .utf8) {
                                // Extract service info and yield
                            }
                        } catch {
                            // Handle error
                        }
                    }
                }
            }
        }
    }
}
*/