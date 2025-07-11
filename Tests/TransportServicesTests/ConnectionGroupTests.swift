import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Connection Group Tests")
struct ConnectionGroupTests {
    
    @Test("Clone connection creates connection in same group")
    func connectionCloning() async throws {
        let port = try await TestUtils.getAvailablePort()
        
        // Create server
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Task to accept multiple connections
        let serverTask = Task {
            var connections: [Connection] = []
            var iterator = listener.newConnections.makeAsyncIterator()
            
            // Accept two connections
            for _ in 0..<2 {
                if let connection = try await iterator.next() {
                    connections.append(connection)
                }
            }
            return connections
        }
        
        // Create client
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: TransportProperties()
        )
        
        let originalConnection = try await clientPreconnection.initiate(timeout: .seconds(5))
        
        // Clone the connection
        let clonedConnection = try await originalConnection.clone()
        
        // Get both server connections
        let serverConnections = try await serverTask.value
        #expect(serverConnections.count == 2)
        
        // Both connections should be in the same group
        let originalGroup = await originalConnection.groupedConnections
        let clonedGroup = await clonedConnection.groupedConnections
        
        #expect(originalGroup.count >= 2)
        #expect(clonedGroup.count >= 2)
        
        // Send data on both connections
        let originalMessage = Message(Data("From original".utf8))
        let clonedMessage = Message(Data("From clone".utf8))
        
        try await originalConnection.send(originalMessage)
        try await clonedConnection.send(clonedMessage)
        
        // Server should receive both messages (one on each connection)
        var receivedTexts: [String] = []
        for connection in serverConnections {
            let msg = try await connection.receive()
            let text = String(data: msg.data, encoding: .utf8) ?? ""
            receivedTexts.append(text)
        }
        
        #expect(receivedTexts.contains("From original"))
        #expect(receivedTexts.contains("From clone"))
        
        // Cleanup
        await originalConnection.closeGroup()
        for connection in serverConnections {
            await connection.close()
        }
        await listener.stop()
    }
    
    @Test("Clone with altered transport properties")
    func cloneWithAlteredProperties() async throws {
        let port = try await TestUtils.getAvailablePort()
        
        // Create server
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Task to accept multiple connections
        let serverTask = Task {
            var connections: [Connection] = []
            var iterator = listener.newConnections.makeAsyncIterator()
            
            // Accept two connections
            for _ in 0..<2 {
                if let connection = try await iterator.next() {
                    connections.append(connection)
                }
            }
            return connections
        }
        
        // Create client
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: TransportProperties()
        )
        
        let originalConnection = try await clientPreconnection.initiate(timeout: .seconds(5))
        
        // Create new transport properties with different settings
        var alteredProperties = TransportProperties()
        alteredProperties.disableNagle = true
        
        // Clone with altered properties
        let clonedConnection = try await originalConnection.clone(altering: alteredProperties)
        
        // Get server connections
        let serverConnections = try await serverTask.value
        #expect(serverConnections.count == 2)
        
        // Verify connections are in same group
        let group = await originalConnection.groupedConnections
        #expect(group.count >= 2)
        
        // Cleanup
        await originalConnection.close()
        await clonedConnection.close()
        for connection in serverConnections {
            await connection.close()
        }
        await listener.stop()
    }
    
    @Test("Clone with custom framer")
    func cloneWithFramer() async throws {
        let (originalConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Create a custom framer
        let customFramer = LengthPrefixFramer()
        
        // Clone with custom framer
        let clonedConnection = try await originalConnection.clone(framer: customFramer)
        
        // Verify connections are in same group
        let group = await originalConnection.groupedConnections
        #expect(group.count >= 2)
        
        // Cleanup
        await originalConnection.close()
        await clonedConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Close group closes all connections")
    func closeGroup() async throws {
        let (originalConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Create multiple clones
        let clone1 = try await originalConnection.clone()
        let clone2 = try await originalConnection.clone()
        
        // Verify all are in the same group
        let group = await originalConnection.groupedConnections
        #expect(group.count >= 3)
        
        // Close the entire group
        await originalConnection.closeGroup()
        
        // All connections should be closed
        let originalState = await originalConnection.state
        let clone1State = await clone1.state
        let clone2State = await clone2.state
        
        #expect(originalState == .closed)
        #expect(clone1State == .closed)
        #expect(clone2State == .closed)
        
        // Cleanup
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Abort group aborts all connections")
    func abortGroup() async throws {
        let (originalConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Create multiple clones
        let clone1 = try await originalConnection.clone()
        let clone2 = try await originalConnection.clone()
        
        // Abort the entire group
        await originalConnection.abortGroup()
        
        // All connections should be closed
        let originalState = await originalConnection.state
        let clone1State = await clone1.state
        let clone2State = await clone2.state
        
        #expect(originalState == .closed)
        #expect(clone1State == .closed)
        #expect(clone2State == .closed)
        
        // Cleanup
        await serverConnection.close()
        await listener.stop()
    }
}