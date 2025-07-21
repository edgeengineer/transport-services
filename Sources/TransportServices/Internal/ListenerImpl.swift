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
    
    /// The actual port the listener is bound to
    var port: UInt16? {
        channel?.localAddress?.port.map { UInt16($0) }
    }
    
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
        
        // Create the stream FIRST, before starting to listen
        // This ensures the continuation is ready when connections arrive
        let stream = AsyncThrowingStream<Connection, Error> { continuation in
            self.streamContinuation = continuation
        }
        
        // Now start listening - any connections that arrive will have a valid continuation
        try await startListening(on: localEndpoint)
        
        return stream
    }
    
    private func startListening(on localEndpoint: LocalEndpoint) async throws {
            // Store a reference to self that can be captured
            let listenerRef = self
            
            let bootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: properties.disableNagle ? 1 : 0)
                .childChannelInitializer { channel in
                    // Process the channel immediately when it's accepted
                    let promise = channel.eventLoop.makePromise(of: Void.self)
                    
                    Task {
                        await listenerRef.handleAcceptedChannel(channel)
                        promise.succeed(())
                    }
                    
                    return promise.futureResult
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
    }
    
    /// Handles an accepted channel by creating a Connection
    func handleAcceptedChannel(_ channel: Channel) async {
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
            let connection = Connection()
            await connection.setImpl(connectionImpl)
            
            // Deliver the connection
            streamContinuation?.yield(connection)
            
        } catch {
            channel.close(promise: nil)
            streamContinuation?.yield(with: .failure(TransportError.establishmentFailure("Failed to configure accepted connection: \(error)")))
        }
    }
    
    /// Configures the accepted channel pipeline
    private func configureAcceptedChannel(_ channel: Channel, for impl: ConnectionImpl) async throws {
        // Extract values outside the closure to avoid actor isolation issues
        let needsTLS = !securityParameters.allowedProtocols.isEmpty && !securityParameters.serverCertificates.isEmpty
        let credentials: ([NIOSSLCertificateSource], NIOSSLPrivateKeySource)?
        let alpnProtocols = securityParameters.alpn
        
        if needsTLS {
            credentials = try extractServerCredentials()
        } else {
            credentials = nil
        }
        
        // Add TLS if required
        if let (certificateChain, privateKey) = credentials {
            // Create TLS configuration
            var tlsConfiguration = TLSConfiguration.makeServerConfiguration(
                certificateChain: certificateChain,
                privateKey: privateKey
            )
            
            // Configure ALPN if provided
            if !alpnProtocols.isEmpty {
                tlsConfiguration.applicationProtocols = alpnProtocols
            }
            
            // Create and add the TLS handler
            let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
            let tlsHandler = NIOSSLServerHandler(context: sslContext)
            try await channel.pipeline.addHandler(tlsHandler, position: .first).get()
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
    
    // MARK: - Private Helpers
    
    /// Extracts server certificates and private key from SecurityParameters
    private func extractServerCredentials() throws -> ([NIOSSLCertificateSource], NIOSSLPrivateKeySource) {
        guard !securityParameters.serverCertificates.isEmpty else {
            throw TransportError.establishmentFailure("No server certificates provided")
        }
        
        // Case 1: Separate certificates and private keys
        if !securityParameters.serverPrivateKeys.isEmpty {
            // We need at least one private key for the server certificate
            guard !securityParameters.serverPrivateKeys.isEmpty else {
                throw TransportError.establishmentFailure("No private key provided for server certificate")
            }
            
            // Build certificate chain - all certificates form the chain
            var certificateChain: [NIOSSLCertificateSource] = []
            
            for certData in securityParameters.serverCertificates {
                // Try to detect format (PEM vs DER)
                let certificate: NIOSSLCertificate
                if certData.starts(with: "-----BEGIN".data(using: .utf8)!) {
                    certificate = try NIOSSLCertificate(bytes: Array(certData), format: .pem)
                } else {
                    certificate = try NIOSSLCertificate(bytes: Array(certData), format: .der)
                }
                certificateChain.append(.certificate(certificate))
            }
            
            // Use the first private key (corresponding to the server certificate)
            let keyData = securityParameters.serverPrivateKeys[0]
            
            let privateKey: NIOSSLPrivateKey
            if keyData.starts(with: "-----BEGIN".data(using: .utf8)!) {
                privateKey = try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem)
            } else {
                privateKey = try NIOSSLPrivateKey(bytes: Array(keyData), format: .der)
            }
            
            // Support for encrypted private keys with password
            if securityParameters.privateKeyPassword != nil {
                // Note: NIOSSL doesn't directly support encrypted private keys
                // This would require additional implementation
                throw TransportError.establishmentFailure("Encrypted private keys not yet supported")
            }
            
            let privateKeySource = NIOSSLPrivateKeySource.privateKey(privateKey)
            
            return (certificateChain, privateKeySource)
        }
        
        // Case 2: PKCS#12 format (certificate and key bundled)
        // Note: NIO SSL doesn't directly support PKCS#12, so this would need
        // additional implementation using Security framework or OpenSSL
        if let firstCertData = securityParameters.serverCertificates.first {
            // Try to parse as regular certificate first
            do {
                _ = try NIOSSLCertificate(bytes: Array(firstCertData), format: .der)
                // If this succeeds but we have no private key, it's an error
                throw TransportError.establishmentFailure("Server certificate provided but no private key found. Use serverPrivateKeys or provide PKCS#12 data.")
            } catch {
                // If regular certificate parsing failed, might be PKCS#12
                // For now, we don't support PKCS#12 directly
                throw TransportError.establishmentFailure("PKCS#12 format not yet supported. Please provide separate certificate and private key.")
            }
        }
        
        throw TransportError.establishmentFailure("Unable to extract server credentials")
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

// MARK: - AcceptedConnectionHandler

/// Handler for accepted connections that creates Connection objects
private final class AcceptedConnectionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Never
    
    private let listener: ListenerImpl
    
    init(listener: ListenerImpl) {
        self.listener = listener
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // When channel becomes active, create a Connection
        let channel = context.channel
        
        Task {
            await self.listener.handleAcceptedChannel(channel)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Close the channel on error
        context.close(promise: nil)
    }
}

