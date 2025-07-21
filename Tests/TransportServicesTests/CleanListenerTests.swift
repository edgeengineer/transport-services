import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Clean Listener Tests")
struct CleanListenerTests {
    
    @Test("Multiple connections to listener")
    func multipleConnections() async throws {
        // Create server with dynamic port
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Track accepted connections
        let acceptTask = Task {
            var connections: [Connection] = []
            for try await connection in listener.newConnections {
                connections.append(connection)
                if connections.count >= 3 {
                    break
                }
            }
            return connections
        }
        
        // Create multiple clients
        var clientConnections: [Connection] = []
        for _ in 0..<3 {
            var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
            clientRemote.port = port
            
            let clientPreconnection = Preconnection(
                remote: [clientRemote],
                transport: TransportProperties()
            )
            
            let connection = try await clientPreconnection.initiate(timeout: .seconds(5))
            clientConnections.append(connection)
        }
        
        // Wait for all connections to be accepted
        let serverConnections = try await acceptTask.value
        
        // Now send unique messages from each client
        for (i, connection) in clientConnections.enumerated() {
            let message = Message(Data("Client \(i)".utf8))
            try await connection.send(message)
        }
        
        // Verify we received all connections
        #expect(serverConnections.count == 3)
        
        // Collect all received messages (order may vary)
        var receivedMessages: Set<String> = []
        for connection in serverConnections {
            let message = try await TestUtils.withTimeout(seconds: 5) {
                try await connection.receive()
            }
            let text = String(data: message.data, encoding: .utf8) ?? ""
            receivedMessages.insert(text)
        }
        
        // Verify we received all expected messages (regardless of order)
        let expectedMessages: Set<String> = ["Client 0", "Client 1", "Client 2"]
        #expect(receivedMessages == expectedMessages)
        
        // Cleanup
        for connection in clientConnections {
            await connection.close()
        }
        for connection in serverConnections {
            await connection.close()
        }
        await listener.stop()
    }
    
    @Test("Connection limit enforcement")
    func connectionLimit() async throws {
        // Create server with connection limit
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Set connection limit to 2
        await listener.setNewConnectionLimit(2)
        
        // Track accepted connections - single iteration
        let acceptTask = Task {
            var connections: [Connection] = []
            do {
                for try await connection in listener.newConnections {
                    connections.append(connection)
                    // Keep accepting until stream ends
                }
            } catch {
                // Stream ended
            }
            return connections
        }
        
        // Try to create 3 clients
        var clients: [Connection?] = []
        for _ in 0..<3 {
            var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
            clientRemote.port = port
            
            let clientPreconnection = Preconnection(
                remote: [clientRemote],
                transport: TransportProperties()
            )
            
            do {
                let connection = try await clientPreconnection.initiate(timeout: .seconds(2))
                clients.append(connection)
            } catch {
                // Expected for connections beyond the limit
                clients.append(nil)
            }
        }
        
        // Wait a bit then stop listener to end the accept task
        try await Task.sleep(for: .milliseconds(500))
        await listener.stop()
        
        // Get accepted connections
        let acceptedConnections = await acceptTask.value
        
        // Verify only 2 connections were accepted
        #expect(acceptedConnections.count == 2)
        
        // Count successful client connections
        let successfulClients = clients.compactMap { $0 }.count
        #expect(successfulClients >= 2)
        
        // Cleanup
        for client in clients {
            if let connection = client {
                await connection.close()
            }
        }
    }
    
    @Test("Listener stop behavior")
    func listenerStop() async throws {
        // Create server
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Start accepting connections
        let acceptTask = Task {
            var connections: [Connection] = []
            do {
                for try await connection in listener.newConnections {
                    connections.append(connection)
                }
            } catch {
                // Expected when listener stops
            }
            return connections
        }
        
        // Create one connection
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: TransportProperties()
        )
        
        let connection = try await clientPreconnection.initiate(timeout: .seconds(5))
        
        // Wait a bit then stop the listener
        try await Task.sleep(for: .milliseconds(100))
        await listener.stop()
        
        // Try to create another connection after stop
        var didFail = false
        do {
            _ = try await clientPreconnection.initiate(timeout: .seconds(1))
        } catch {
            didFail = true
        }
        
        #expect(didFail)
        
        // Verify accept task got at least one connection
        let acceptedConnections = await acceptTask.value
        #expect(acceptedConnections.count >= 1)
        
        // Cleanup
        await connection.close()
        for conn in acceptedConnections {
            await conn.close()
        }
    }
}
