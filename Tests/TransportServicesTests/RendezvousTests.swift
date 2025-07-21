import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Rendezvous Connection Tests", .disabled("Temporarily disabled pending rendezvous implementation fixes"))
struct RendezvousTests {
    
    @Test("Basic rendezvous connection")
    func basicRendezvous() async throws {
        // Get two ports for the peers
        let port1 = try await TestUtils.getAvailablePort()
        let port2 = try await TestUtils.getAvailablePort()
        
        // Create peer 1
        var peer1Local = LocalEndpoint(kind: .host("127.0.0.1"))
        peer1Local.port = port1
        
        var peer1Remote = RemoteEndpoint(kind: .host("127.0.0.1"))
        peer1Remote.port = port2
        
        let peer1Preconnection = Preconnection(
            local: [peer1Local],
            remote: [peer1Remote],
            transport: TransportProperties()
        )
        
        // Create peer 2
        var peer2Local = LocalEndpoint(kind: .host("127.0.0.1"))
        peer2Local.port = port2
        
        var peer2Remote = RemoteEndpoint(kind: .host("127.0.0.1"))
        peer2Remote.port = port1
        
        let peer2Preconnection = Preconnection(
            local: [peer2Local],
            remote: [peer2Remote],
            transport: TransportProperties()
        )
        
        // Start rendezvous on both peers concurrently
        async let peer1Task = peer1Preconnection.rendezvous()
        async let peer2Task = peer2Preconnection.rendezvous()
        
        // Wait for both connections
        let peer1Connection = try await peer1Task
        let peer2Connection = try await peer2Task
        
        // Check connection states
        let state1 = await peer1Connection.state
        let state2 = await peer2Connection.state
        
        #expect(state1 == .established)
        #expect(state2 == .established)
        
        // Exchange messages
        let msg1 = Message(Data("Hello from peer 1".utf8))
        let msg2 = Message(Data("Hello from peer 2".utf8))
        
        try await peer1Connection.send(msg1)
        try await peer2Connection.send(msg2)
        
        let received1 = try await peer2Connection.receive()
        let received2 = try await peer1Connection.receive()
        
        let text1 = String(data: received1.data, encoding: .utf8) ?? ""
        let text2 = String(data: received2.data, encoding: .utf8) ?? ""
        
        #expect(text1 == "Hello from peer 1")
        #expect(text2 == "Hello from peer 2")
        
        // Cleanup
        await peer1Connection.close()
        await peer2Connection.close()
    }
    
    @Test("Rendezvous with multiple candidates")
    func rendezvousWithMultipleCandidates() async throws {
        // Simulate ICE-like scenario with multiple candidates
        let port1 = try await TestUtils.getAvailablePort()
        let port2 = try await TestUtils.getAvailablePort()
        _ = try await TestUtils.getAvailablePort()
        
        // Peer 1 with multiple local candidates
        var peer1Candidate1 = LocalEndpoint(kind: .host("127.0.0.1"))
        peer1Candidate1.port = port1
        
        var peer1Candidate2 = LocalEndpoint(kind: .host("::1"))  // IPv6
        peer1Candidate2.port = port1
        
        // Peer 2 with multiple candidates
        var peer2Candidate1 = LocalEndpoint(kind: .host("127.0.0.1"))
        peer2Candidate1.port = port2
        
        var peer2Candidate2 = LocalEndpoint(kind: .host("::1"))
        peer2Candidate2.port = port2
        
        // Remote candidates for each peer
        var peer1Remote1 = RemoteEndpoint(kind: .host("127.0.0.1"))
        peer1Remote1.port = port2
        
        var peer1Remote2 = RemoteEndpoint(kind: .host("::1"))
        peer1Remote2.port = port2
        
        var peer2Remote1 = RemoteEndpoint(kind: .host("127.0.0.1"))
        peer2Remote1.port = port1
        
        var peer2Remote2 = RemoteEndpoint(kind: .host("::1"))
        peer2Remote2.port = port1
        
        // Create preconnections with multiple candidates
        let peer1Preconnection = Preconnection(
            local: [peer1Candidate1, peer1Candidate2],
            remote: [peer1Remote1, peer1Remote2],
            transport: TransportProperties()
        )
        
        let peer2Preconnection = Preconnection(
            local: [peer2Candidate1, peer2Candidate2],
            remote: [peer2Remote1, peer2Remote2],
            transport: TransportProperties()
        )
        
        // Attempt rendezvous
        async let peer1Task = peer1Preconnection.rendezvous()
        async let peer2Task = peer2Preconnection.rendezvous()
        
        let peer1Connection = try await peer1Task
        let peer2Connection = try await peer2Task
        
        // Verify connection established
        let state1 = await peer1Connection.state
        let state2 = await peer2Connection.state
        
        #expect(state1 == .established)
        #expect(state2 == .established)
        
        // Cleanup
        await peer1Connection.close()
        await peer2Connection.close()
    }
    
    @Test("Rendezvous with pre-configured candidates")
    func rendezvousWithPreConfiguredCandidates() async throws {
        let port1 = try await TestUtils.getAvailablePort()
        let port2 = try await TestUtils.getAvailablePort()
        
        // Note: Dynamic candidate addition via addRemote() (RFC 9622 §7.5)
        // is not implemented yet. For now, we configure all candidates upfront.
        
        // Create peer 1 with remote candidate pre-configured
        var peer1Local = LocalEndpoint(kind: .host("127.0.0.1"))
        peer1Local.port = port1
        
        var peer1Remote = RemoteEndpoint(kind: .host("127.0.0.1"))
        peer1Remote.port = port2
        
        let peer1Preconnection = Preconnection(
            local: [peer1Local],
            remote: [peer1Remote],
            transport: TransportProperties()
        )
        
        // Create peer 2 with remote candidate pre-configured
        var peer2Local = LocalEndpoint(kind: .host("127.0.0.1"))
        peer2Local.port = port2
        
        var peer2Remote = RemoteEndpoint(kind: .host("127.0.0.1"))
        peer2Remote.port = port1
        
        let peer2Preconnection = Preconnection(
            local: [peer2Local],
            remote: [peer2Remote],
            transport: TransportProperties()
        )
        
        // Start rendezvous
        async let peer1Task = peer1Preconnection.rendezvous()
        async let peer2Task = peer2Preconnection.rendezvous()
        
        let peer1Connection = try await peer1Task
        let peer2Connection = try await peer2Task
        
        // Test bidirectional communication
        let testData1 = Data("Peer 1 data".utf8)
        let testData2 = Data("Peer 2 data".utf8)
        
        try await peer1Connection.send(Message(testData1))
        try await peer2Connection.send(Message(testData2))
        
        let received1 = try await peer2Connection.receive()
        let received2 = try await peer1Connection.receive()
        
        #expect(received1.data == testData1)
        #expect(received2.data == testData2)
        
        // Cleanup
        await peer1Connection.close()
        await peer2Connection.close()
    }
}