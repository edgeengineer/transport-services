#!/usr/bin/env swift

import TransportServices
import Foundation

/// Peer-to-Peer Rendezvous Example
///
/// This example demonstrates:
/// - Setting up a rendezvous connection for NAT traversal
/// - Exchanging endpoint candidates via signaling
/// - Establishing direct peer-to-peer connections
/// - Handling the full rendezvous flow

// Simulated signaling channel (in real app, this would be WebSocket, HTTP, etc.)
actor SignalingChannel {
    private var pendingCandidates: [String: [LocalEndpoint]] = [:]
    
    func sendCandidates(_ candidates: [LocalEndpoint], to peerId: String) {
        pendingCandidates[peerId] = candidates
        print("[Signaling] Sent \(candidates.count) candidates to peer \(peerId)")
    }
    
    func receiveCandidates(from peerId: String) async -> [RemoteEndpoint] {
        // Simulate waiting for candidates
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Convert local endpoints to remote endpoints (simulated)
        let locals = pendingCandidates[peerId] ?? []
        return locals.map { local in
            var remote = RemoteEndpoint(kind: local.kind)
            remote.port = local.port
            return remote
        }
    }
}

@main
struct RendezvousExample {
    static let signaling = SignalingChannel()
    
    static func main() async {
        // Run both peers concurrently
        async let peer1 = runPeer(id: "Alice", remoteId: "Bob")
        async let peer2 = runPeer(id: "Bob", remoteId: "Alice")
        
        let _ = await (peer1, peer2)
    }
    
    static func runPeer(id: String, remoteId: String) async {
        do {
            print("[\(id)] Starting rendezvous process...")
            
            // Create local endpoints including STUN server for NAT discovery
            var localEndpoint = LocalEndpoint(kind: .ip("0.0.0.0"))
            localEndpoint.port = 0 // Ephemeral port
            
            // In real scenario, add STUN endpoint:
            // var stunEndpoint = LocalEndpoint(kind: .host("stun.example.com"))
            // stunEndpoint.port = 3478
            
            // Create preconnection
            let preconnection = Preconnection(
                local: [localEndpoint],
                transport: .lowLatency() // Optimized for P2P
            )
            
            // Resolve local candidates (gets reflexive addresses via STUN)
            let (localCandidates, _) = try await preconnection.resolve()
            print("[\(id)] Resolved \(localCandidates.count) local candidates")
            
            // Send our candidates to the remote peer via signaling
            await signaling.sendCandidates(localCandidates, to: remoteId)
            
            // Receive remote peer's candidates
            let remoteCandidates = await signaling.receiveCandidates(from: remoteId)
            print("[\(id)] Received \(remoteCandidates.count) remote candidates")
            
            // Add remote endpoints to preconnection
            for candidate in remoteCandidates {
                await preconnection.add(remote: candidate)
            }
            
            // Perform rendezvous - simultaneous connect/listen
            print("[\(id)] Attempting rendezvous...")
            let connection = try await preconnection.rendezvous()
            
            print("[\(id)] ✅ Rendezvous successful! Connected to peer.")
            
            // Exchange messages
            if id == "Alice" {
                let message = Message("Hello from Alice!".data(using: .utf8)!)
                try await connection.send(message)
                print("[\(id)] Sent greeting")
                
                let response = try await connection.receive()
                if let text = String(data: response.data, encoding: .utf8) {
                    print("[\(id)] Received: \(text)")
                }
            } else {
                let message = try await connection.receive()
                if let text = String(data: message.data, encoding: .utf8) {
                    print("[\(id)] Received: \(text)")
                }
                
                let response = Message("Hello from Bob!".data(using: .utf8)!)
                try await connection.send(response)
                print("[\(id)] Sent response")
            }
            
            // Close connection
            await connection.close()
            print("[\(id)] Connection closed")
            
        } catch {
            print("[\(id)] Error: \(error)")
        }
    }
}

// Real-world rendezvous flow:
/*
class P2PConnection {
    private let myId: String
    private let signaling: SignalingProtocol
    
    init(id: String, signaling: SignalingProtocol) {
        self.myId = id
        self.signaling = signaling
    }
    
    func connectToPeer(_ peerId: String) async throws -> Connection {
        // 1. Create preconnection with STUN servers
        var stunEndpoint = LocalEndpoint(kind: .host("stun.l.google.com"))
        stunEndpoint.port = 19302
        
        let preconnection = Preconnection(
            local: [stunEndpoint],
            transport: .lowLatency()
        )
        
        // 2. Gather local candidates (ICE gathering)
        let (candidates, _) = try await preconnection.resolve()
        
        // 3. Send candidates via signaling
        try await signaling.sendCandidates(candidates, to: peerId, from: myId)
        
        // 4. Receive remote candidates
        let remoteCandidates = try await signaling.receiveCandidates(from: peerId)
        
        // 5. Add all remote candidates
        for candidate in remoteCandidates {
            await preconnection.add(remote: candidate)
        }
        
        // 6. Perform rendezvous (ICE connectivity checks)
        return try await preconnection.rendezvous()
    }
}
*/