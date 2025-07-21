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
    
    /// Creates a client-server pair on an available port using the default transport services implementation
    static func createClientServerPair() async throws -> (client: Connection, server: Connection, listener: Listener) {
        let port = try await getAvailablePort()
        
        // Create server with port 0 to let system assign
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = 0  // Let system assign port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Get the actual port that was bound
        let actualPort = await listener.port ?? port
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client connecting to the actual port
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = actualPort
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: TransportProperties()
        )
        
        let clientConnection = try await clientPreconnection.initiate(timeout: Duration.seconds(5))
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
    
    /// Executes an async operation with a timeout
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TransportError.establishmentFailure("Operation timed out after \(seconds) seconds")
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

/// Test suite base class that provides per-suite transport services lifecycle
actor TestSuiteBase {
    private let transportServices: TransportServicesImpl
    
    init() {
        // Create a dedicated transport services instance for this test suite
        self.transportServices = TransportServicesImpl(numberOfThreads: 2)
    }
    
    /// Gets the transport services instance for this test suite
    func getTransportServices() -> TransportServicesImpl {
        return transportServices
    }
    
    /// Creates a client-server pair using this suite's transport services
    func createClientServerPair() async throws -> (client: Connection, server: Connection, listener: Listener) {
        // For now, use the default implementation since we need to modify Preconnection
        // to support dependency injection
        return try await TestUtils.createClientServerPair()
    }
    
    /// Shuts down the transport services for this test suite
    func shutdown() async throws {
        try await transportServices.shutdown()
    }
    
    deinit {
        // Ensure shutdown in case it wasn't called explicitly
        // Use weak reference to avoid capture issues
        let services = transportServices
        Task { [services] in
            try? await services.shutdown()
        }
    }
}
