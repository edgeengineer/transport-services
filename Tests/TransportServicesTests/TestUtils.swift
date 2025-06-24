import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOPosix
@testable import TransportServices

/// Utility functions for testing
enum TestUtils {
    
    /// Gets an available port by binding to port 0 and letting the system assign one
    static func getAvailablePort() async throws -> UInt16 {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        do {
            let serverBootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 1)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            
            // Bind to port 0 to get an available port
            let channel = try await serverBootstrap.bind(host: "127.0.0.1", port: 0).get()
            let port = channel.localAddress?.port ?? 0
            
            // Close the channel immediately
            try await channel.close()
            
            // Shutdown the event loop group
            try await eventLoopGroup.shutdownGracefully()
            
            guard port > 0 else {
                throw TransportError.establishmentFailure("Failed to get available port")
            }
            
            return UInt16(port)
        } catch {
            try await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }
    
    /// Creates a client-server pair on an available port
    static func createClientServerPair() async throws -> (client: Connection, server: Connection, listener: Listener) {
        let port = try await getAvailablePort()
        
        // Create server
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: TransportProperties()
        )
        
        let clientConnection = try await clientPreconnection.initiate(timeout: .seconds(5))
        let serverConnection = try await serverTask.value
        
        return (clientConnection, serverConnection, listener)
    }
    
    /// Waits for a condition to be true with timeout
    static func waitFor(
        condition: () async -> Bool,
        timeout: Duration = .seconds(5),
        interval: Duration = .milliseconds(100)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: interval)
        }
        
        throw TransportError.establishmentFailure("Timeout waiting for condition")
    }
}