#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOPosix
@preconcurrency import NIOSSL

/// Internal implementation of a Transport Services Listener using SwiftNIO.
actor ListenerImpl {
    
    // MARK: - Properties
    
    /// The local endpoints this listener is bound to
    let localEndpoints: [LocalEndpoint]
    
    /// The remote endpoints for filtering (if any)
    let remoteEndpoints: [RemoteEndpoint]
    
    /// Transport properties for accepted connections
    let properties: TransportProperties
    
    /// Security parameters for accepted connections
    let securityParameters: SecurityParameters
    
    /// Message framers for accepted connections
    let framers: [any MessageFramer]
    
    /// The NIO channel for listening
    private var channel: Channel?
    
    /// The event loop group managing this listener
    private let eventLoopGroup: EventLoopGroup
    
    /// Connection limit for rate limiting
    private var connectionLimit: Int?
    
    /// Current connection count against the limit
    private var connectionCount: Int = 0
    
    /// Whether the listener is active
    private var isActive: Bool = true
    
    /// Stream continuation for delivering connections
    private var streamContinuation: AsyncThrowingStream<Connection, Error>.Continuation?
    
    // MARK: - Initialization
    
    init(localEndpoints: [LocalEndpoint],
         remoteEndpoints: [RemoteEndpoint],
         properties: TransportProperties,
         securityParameters: SecurityParameters,
         framers: [any MessageFramer],
         eventLoopGroup: EventLoopGroup) {
        self.localEndpoints = localEndpoints
        self.remoteEndpoints = remoteEndpoints
        self.properties = properties
        self.securityParameters = securityParameters
        self.framers = framers
        self.eventLoopGroup = eventLoopGroup
    }
    
    // MARK: - Lifecycle
    
    /// Starts listening on the specified endpoints
    func start() async throws -> AsyncThrowingStream<Connection, Error> {
        guard let localEndpoint = localEndpoints.first else {
            throw TransportError.establishmentFailure("No local endpoints specified")
        }
        
        let stream = AsyncThrowingStream<Connection, Error> { continuation in
            self.streamContinuation = continuation
            
            Task {
                await self.startListening(on: localEndpoint)
            }
        }
        
        return stream
    }
    
    private func startListening(on localEndpoint: LocalEndpoint) async {
        do {
            let bootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: properties.disableNagle ? 1 : 0)
                .childChannelInitializer { [weak self] channel in
                    guard let self = self else {
                        return channel.eventLoop.makeFailedFuture(TransportError.establishmentFailure("Listener deallocated"))
                    }
                    
                    // Create a new connection for this accepted channel
                    Task {
                        await self.handleAcceptedChannel(channel)
                    }
                    
                    return channel.eventLoop.makeSucceededFuture(())
                }
            
            // Bind to the local endpoint
            let channel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
                let bindFuture: EventLoopFuture<Channel>
                
                switch localEndpoint.kind {
                case .host(let hostname):
                    bindFuture = bootstrap.bind(host: hostname, port: Int(localEndpoint.port ?? 0))
                case .ip(let address):
                    bindFuture = bootstrap.bind(host: address, port: Int(localEndpoint.port ?? 0))
                }
                
                bindFuture.whenComplete { result in
                    continuation.resume(with: result)
                }
            }
            
            self.channel = channel
            
        } catch {
            streamContinuation?.finish(throwing: TransportError.establishmentFailure("Failed to start listener: \(error)"))
        }
    }
    
    /// Handles an accepted channel by creating a Connection
    private func handleAcceptedChannel(_ channel: Channel) async {
        // Check connection limit
        if let limit = connectionLimit, connectionCount >= limit {
            // Reject the connection
            channel.close(promise: nil)
            return
        }
        
        // Increment connection count
        connectionCount += 1
        
        // Create a new connection implementation
        let connectionImpl = ConnectionImpl(
            id: UUID(),
            properties: properties,
            securityParameters: securityParameters,
            framers: framers,
            eventLoopGroup: eventLoopGroup
        )
        
        // Set the established channel
        await connectionImpl.setEstablishedChannel(channel)
        
        // Configure the channel pipeline
        do {
            try await configureAcceptedChannel(channel, for: connectionImpl)
            
            // Create the public Connection
            let bridge = ConnectionBridge(impl: connectionImpl)
            let connection = Connection()
            await connection.setBridge(bridge)
            
            // Deliver the connection
            streamContinuation?.yield(connection)
            
        } catch {
            channel.close(promise: nil)
            streamContinuation?.yield(with: .failure(TransportError.establishmentFailure("Failed to configure accepted connection: \(error)")))
        }
    }
    
    /// Configures the accepted channel pipeline
    private func configureAcceptedChannel(_ channel: Channel, for impl: ConnectionImpl) async throws {
        // Add TLS if required
        if !securityParameters.allowedProtocols.isEmpty {
            let tlsConfiguration = TLSConfiguration.makeServerConfiguration(
                certificateChain: [],  // Should be provided by security parameters
                privateKey: .privateKey(try! NIOSSLPrivateKey(bytes: Array(), format: .pem))  // Should be provided
            )
            
            let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
            let tlsHandler = NIOSSLServerHandler(context: sslContext)
            try await channel.pipeline.addHandler(tlsHandler).get()
        }
        
        // Add message framing handler
        let framingHandler = SimpleFramingHandler()
        try await channel.pipeline.addHandler(framingHandler).get()
        
        // Add the main connection handler
        let connectionHandler = ConnectionHandler(impl: impl)
        try await channel.pipeline.addHandler(connectionHandler).get()
    }
    
    /// Stops the listener
    func stop() async {
        isActive = false
        
        if let channel = channel {
            do {
                try await channel.close()
            } catch {
                // Ignore close errors
            }
        }
        
        streamContinuation?.finish()
    }
    
    /// Sets the connection limit
    func setConnectionLimit(_ limit: Int?) async {
        self.connectionLimit = limit
    }
}

/// Main handler for connection events
private final class ConnectionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Message
    
    private let impl: ConnectionImpl
    
    init(impl: ConnectionImpl) {
        self.impl = impl
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        let capturedImpl = impl
        
        Task { @Sendable in
            await capturedImpl.handleIncomingMessage(message)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Handle errors
        context.close(promise: nil)
    }
}