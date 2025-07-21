#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOPosix

/// Main implementation manager for Transport Services using SwiftNIO.
///
/// This class manages event loop groups and provides factory methods
/// for creating connections and listeners. It can be used as a singleton
/// for production or created per-test-suite for testing.
actor TransportServicesImpl {
    
    // MARK: - Singleton
    
    static let shared = TransportServicesImpl()
    
    // MARK: - Properties
    
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var isShutdown = false
    
    // MARK: - Initialization
    
    /// Creates a new TransportServicesImpl instance
    /// - Parameter numberOfThreads: Number of threads for the event loop group. Defaults to system core count.
    init(numberOfThreads: Int? = nil) {
        // Create a multi-threaded event loop group
        let threadCount = numberOfThreads ?? System.coreCount
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
    }
    
    deinit {
        // Shutdown the event loop group if not already shut down
        if !isShutdown {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }
    
    // MARK: - Shutdown
    
    /// Shuts down the transport services implementation
    /// This should be called when the application is terminating
    /// or during test cleanup to ensure proper resource cleanup
    func shutdown() async throws {
        guard !isShutdown else { return }
        isShutdown = true
        try await eventLoopGroup.shutdownGracefully()
    }
    
    /// Synchronous shutdown for use in deinit or synchronous contexts
    func syncShutdown() throws {
        guard !isShutdown else { return }
        isShutdown = true
        try eventLoopGroup.syncShutdownGracefully()
    }
    
    /// Checks if the implementation has been shut down
    var hasShutdown: Bool {
        isShutdown
    }
    
    // MARK: - Connection Creation
    
    /// Creates a new connection implementation
    func createConnection(properties: TransportProperties,
                          securityParameters: SecurityParameters,
                          framers: [any MessageFramer]) -> ConnectionImpl {
        let id = UUID()
        return ConnectionImpl(
            id: id,
            properties: properties,
            securityParameters: securityParameters,
            framers: framers,
            eventLoopGroup: eventLoopGroup
        )
    }
    
    /// Initiates a connection to a remote endpoint
    func initiate(remoteEndpoints: [RemoteEndpoint],
                  localEndpoints: [LocalEndpoint],
                  properties: TransportProperties,
                  securityParameters: SecurityParameters,
                  framers: [any MessageFramer]) async throws -> Connection {
        
        // Create connection implementation
        let impl = createConnection(
            properties: properties,
            securityParameters: securityParameters,
            framers: framers
        )
        
        // For now, we'll use the first endpoints
        // Full implementation would perform candidate racing
        guard let remoteEndpoint = remoteEndpoints.first else {
            throw TransportError.establishmentFailure("No remote endpoints specified")
        }
        
        let localEndpoint = localEndpoints.first
        
        // Establish the connection
        try await impl.establish(to: remoteEndpoint, from: localEndpoint)
        
        // Create connection and set implementation
        let connection = Connection()
        await connection.setImpl(impl)
        return connection
    }
    
    /// Initiates a connection and sends the first message atomically
    func initiateWithSend(remoteEndpoints: [RemoteEndpoint],
                          localEndpoints: [LocalEndpoint],
                          properties: TransportProperties,
                          securityParameters: SecurityParameters,
                          framers: [any MessageFramer],
                          firstMessage: Message) async throws -> Connection {
        
        // Create connection implementation
        let impl = createConnection(
            properties: properties,
            securityParameters: securityParameters,
            framers: framers
        )
        
        // For now, we'll use the first endpoints
        // Full implementation would perform candidate racing
        guard let remoteEndpoint = remoteEndpoints.first else {
            throw TransportError.establishmentFailure("No remote endpoints specified")
        }
        
        let localEndpoint = localEndpoints.first
        
        // Establish the connection with 0-RTT if available
        try await impl.establishWithSend(
            to: remoteEndpoint,
            from: localEndpoint,
            firstMessage: firstMessage
        )
        
        // Create connection and set implementation
        let connection = Connection()
        await connection.setImpl(impl)
        return connection
    }
    
    /// Creates a listener for incoming connections
    func listen(localEndpoints: [LocalEndpoint],
                remoteEndpoints: [RemoteEndpoint],
                properties: TransportProperties,
                securityParameters: SecurityParameters,
                framers: [any MessageFramer]) async throws -> Listener {
        
        // Create the listener implementation
        let listenerImpl = ListenerImpl(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            properties: properties,
            securityParameters: securityParameters,
            framers: framers,
            eventLoopGroup: eventLoopGroup
        )
        
        // Start the listener and get the connection stream
        let connectionStream = try await listenerImpl.start()
        
        // Create the public Listener with the stream
        let listener = Listener(impl: listenerImpl, stream: connectionStream)
        
        return listener
    }
    
    /// Performs a rendezvous connection
    func rendezvous(localEndpoints: [LocalEndpoint],
                    remoteEndpoints: [RemoteEndpoint],
                    properties: TransportProperties,
                    securityParameters: SecurityParameters,
                    framers: [any MessageFramer]) async throws -> Connection {
        
        let rendezvous = RendezvousImpl(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            properties: properties,
            securityParameters: securityParameters,
            framers: framers,
            eventLoopGroup: eventLoopGroup
        )
        
        return try await rendezvous.performRendezvous()
    }
    
    // MARK: - Multicast Support
    
    /// Creates a multicast sender connection
    func createMulticastSender(multicastEndpoint: MulticastEndpoint,
                               properties: TransportProperties) async throws -> Connection {
        let multicastImpl = MulticastConnectionImpl(
            multicastEndpoint: multicastEndpoint,
            properties: properties,
            eventLoopGroup: eventLoopGroup
        )
        
        return try await multicastImpl.establishSender()
    }
    
    /// Creates a multicast receiver listener
    func createMulticastReceiver(multicastEndpoint: MulticastEndpoint,
                                 properties: TransportProperties) async throws -> MulticastListener {
        let multicastImpl = MulticastConnectionImpl(
            multicastEndpoint: multicastEndpoint,
            properties: properties,
            eventLoopGroup: eventLoopGroup
        )
        
        return try await multicastImpl.establishReceiver()
    }
}
