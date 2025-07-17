#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore
import NIOPosix
@preconcurrency import NIOSSL

/// Implementation of peer-to-peer rendezvous connections.
///
/// This class handles the simultaneous listening and connection attempts
/// required for NAT traversal and peer-to-peer connectivity.
actor RendezvousImpl {
    
    // MARK: - Properties
    
    private let localEndpoints: [LocalEndpoint]
    private let remoteEndpoints: [RemoteEndpoint]
    private let properties: TransportProperties
    private let securityParameters: SecurityParameters
    private let framers: [any MessageFramer]
    private let eventLoopGroup: EventLoopGroup
    
    /// Active connection attempts
    private var connectionAttempts: [UUID: ConnectionAttempt] = [:]
    
    /// Active listeners
    private var listeners: [Channel] = []
    
    /// The first successful connection
    private var establishedConnection: Connection?
    
    /// Completion handler for the rendezvous
    private var completionHandler: CheckedContinuation<Connection, Error>?
    
    // MARK: - Types
    
    private struct ConnectionAttempt {
        let id: UUID
        let localEndpoint: LocalEndpoint?
        let remoteEndpoint: RemoteEndpoint
        let task: Task<Void, Never>
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
    
    // MARK: - Public Methods
    
    /// Performs the rendezvous operation
    func performRendezvous() async throws -> Connection {
        return try await withCheckedThrowingContinuation { continuation in
            self.completionHandler = continuation
            
            Task {
                await self.startRendezvous()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Starts the rendezvous process
    private func startRendezvous() async {
        // Start listeners on all local endpoints
        await startListeners()
        
        // Give listeners time to be ready
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Start connection attempts to all remote endpoints
        await startConnectionAttempts()
    }
    
    /// Starts listeners on all local endpoints
    private func startListeners() async {
        for localEndpoint in localEndpoints {
            Task {
                await self.startListener(on: localEndpoint)
            }
        }
    }
    
    /// Starts a listener on a specific local endpoint
    private func startListener(on localEndpoint: LocalEndpoint) async {
        do {
            let bootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer(makeChildChannelInitializer())
            
            let channel: Channel
            switch localEndpoint.kind {
            case .host(let hostname):
                channel = try await bootstrap.bind(host: hostname, port: Int(localEndpoint.port ?? 0)).get()
            case .ip(let address):
                channel = try await bootstrap.bind(host: address, port: Int(localEndpoint.port ?? 0)).get()
            }
            
            // [Rendezvous] Started listener on \(channel.localAddress?.description ?? "unknown")")
            listeners.append(channel)
            
        } catch {
            // [Rendezvous] Failed to start listener on \(localEndpoint.description): \(error)")
            // Continue with other endpoints on error
        }
    }
    
    /// Creates a child channel initializer
    private func makeChildChannelInitializer() -> @Sendable (Channel) -> EventLoopFuture<Void> {
        let framers = self.framers
        let securityParams = self.securityParameters
        
        return { @Sendable [weak self] channel in
            guard let self = self else {
                return channel.eventLoop.makeFailedFuture(TransportError.establishmentFailure("Rendezvous deallocated"))
            }
            return Self.configureIncomingChannel(
                channel: channel,
                framers: framers,
                securityParameters: securityParams,
                impl: self
            )
        }
    }
    
    /// Configures an incoming channel
    private static func configureIncomingChannel(channel: Channel,
                                                  framers: [any MessageFramer],
                                                  securityParameters: SecurityParameters,
                                                  impl: RendezvousImpl) -> EventLoopFuture<Void> {
        let promise = channel.eventLoop.makePromise(of: Void.self)
        
        // Use Task to handle async configuration
        Task {
            do {
                // Add TLS if required
                if !securityParameters.allowedProtocols.isEmpty && !securityParameters.serverCertificates.isEmpty {
                    do {
                        // Extract server credentials
                        let (certificateChain, privateKey) = try extractServerCredentials(from: securityParameters)
                        
                        var tlsConfiguration = TLSConfiguration.makeServerConfiguration(
                            certificateChain: certificateChain,
                            privateKey: privateKey
                        )
                        
                        // Configure ALPN if provided
                        if !securityParameters.alpn.isEmpty {
                            tlsConfiguration.applicationProtocols = securityParameters.alpn
                        }
                        
                        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                        let tlsHandler = NIOSSLServerHandler(context: sslContext)
                        try await channel.pipeline.addHandler(tlsHandler).get()
                    } catch {
                        // Log TLS configuration error but continue without TLS
                        print("Warning: Failed to configure TLS for rendezvous: \(error)")
                    }
                }
                
                // Add message framing
                let framingHandler = SimpleFramingHandler()
                try await channel.pipeline.addHandler(framingHandler).get()
                
                // Add rendezvous handler
                let rendezvousHandler = RendezvousIncomingHandler(impl: impl)
                try await channel.pipeline.addHandler(rendezvousHandler).get()
                
                promise.succeed(())
            } catch {
                promise.fail(error)
            }
        }
        
        return promise.futureResult
    }
    
    /// Starts connection attempts to all remote endpoints
    private func startConnectionAttempts() async {
        for remoteEndpoint in remoteEndpoints {
            for localEndpoint in localEndpoints + [nil] { // Try with specific local endpoints and ephemeral
                let attemptId = UUID()
                let task = Task {
                    await self.attemptConnection(
                        id: attemptId,
                        from: localEndpoint,
                        to: remoteEndpoint
                    )
                }
                
                connectionAttempts[attemptId] = ConnectionAttempt(
                    id: attemptId,
                    localEndpoint: localEndpoint,
                    remoteEndpoint: remoteEndpoint,
                    task: task
                )
            }
        }
    }
    
    /// Attempts a single connection
    private func attemptConnection(id: UUID, from localEndpoint: LocalEndpoint?, to remoteEndpoint: RemoteEndpoint) async {
        // [Rendezvous] Attempting connection from \(localEndpoint?.description ?? "ephemeral") to \(remoteEndpoint.description)")
        do {
            let impl = ConnectionImpl(
                id: UUID(),
                properties: properties,
                securityParameters: securityParameters,
                framers: framers,
                eventLoopGroup: eventLoopGroup
            )
            
            try await impl.establish(to: remoteEndpoint, from: localEndpoint)
            
            // [Rendezvous] Outgoing connection established successfully")
            
            // Create the connection
            let bridge = ConnectionBridge(impl: impl)
            let connection = Connection()
            await connection.setBridge(bridge)
            
            // First successful connection wins
            await self.handleSuccessfulConnection(connection)
            
        } catch {
            // Connection attempt failed, remove from active attempts
            connectionAttempts.removeValue(forKey: id)
            
            // Check if all attempts have failed
            if connectionAttempts.isEmpty && establishedConnection == nil {
                // Take the completion handler to ensure it's only called once
                let handler = completionHandler
                completionHandler = nil
                
                handler?.resume(throwing: TransportError.establishmentFailure(
                    "All rendezvous connection attempts failed"
                ))
            }
        }
    }
    
    /// Handles a successful incoming connection
    func handleIncomingConnection(_ channel: Channel) async {
        // Create connection from the channel
        let impl = ConnectionImpl(
            id: UUID(),
            properties: properties,
            securityParameters: securityParameters,
            framers: framers,
            eventLoopGroup: eventLoopGroup
        )
        
        // Set the channel directly (it's already established)
        await impl.setEstablishedChannel(channel)
        
        // Now add the connection handler to complete the pipeline
        do {
            let connectionHandler = ConnectionHandler(impl: impl)
            try await channel.pipeline.addHandler(connectionHandler).get()
        } catch {
            // Failed to configure the channel
            try? await channel.close()
            return
        }
        
        let bridge = ConnectionBridge(impl: impl)
        let connection = Connection()
        await connection.setBridge(bridge)
        
        await handleSuccessfulConnection(connection)
    }
    
    /// Handles the first successful connection
    private func handleSuccessfulConnection(_ connection: Connection) async {
        // [Rendezvous] handleSuccessfulConnection called")
        
        // Ensure we only handle the first successful connection
        guard establishedConnection == nil else { 
            // [Rendezvous] Already have a connection, closing this one")
            // Already have a connection, close this one
            await connection.close()
            return 
        }
        
        // Atomically check and set the established connection
        guard completionHandler != nil else { 
            // [Rendezvous] No completion handler")
            return 
        }
        
        establishedConnection = connection
        
        // Take the completion handler to ensure it's only called once
        let handler = completionHandler
        completionHandler = nil
        
        // Cancel all other attempts
        for (_, attempt) in connectionAttempts {
            attempt.task.cancel()
        }
        connectionAttempts.removeAll()
        
        // Close all listeners
        for listener in listeners {
            try? await listener.close()
        }
        listeners.removeAll()
        
        // [Rendezvous] Completing rendezvous with successful connection")
        // Complete the rendezvous (only if we have a handler)
        handler?.resume(returning: connection)
    }
}

// MARK: - Channel Handlers

/// Handles incoming connections during rendezvous
private final class RendezvousIncomingHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    
    private let impl: RendezvousImpl
    
    init(impl: RendezvousImpl) {
        self.impl = impl
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // [Rendezvous] RendezvousIncomingHandler.channelActive called")
        // New incoming connection established
        let channel = context.channel
        
        // Remove ourselves from the pipeline since we're done
        context.pipeline.removeHandler(self, promise: nil)
        
        Task {
            await impl.handleIncomingConnection(channel)
        }
        
        // Pass the event up the pipeline
        context.fireChannelActive()
    }
}


// MARK: - Connection Handler

/// Main handler for connection events
private final class ConnectionHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = Message
    typealias InboundOut = Message
    typealias OutboundIn = Message
    typealias OutboundOut = Message
    
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
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        // Pass through the message and flush
        context.writeAndFlush(data, promise: promise)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Handle errors
        context.close(promise: nil)
    }
}

// MARK: - Private Helpers

/// Extracts server certificates and private key from SecurityParameters
private func extractServerCredentials(from securityParameters: SecurityParameters) throws -> ([NIOSSLCertificateSource], NIOSSLPrivateKeySource) {
    guard !securityParameters.serverCertificates.isEmpty else {
        throw TransportError.establishmentFailure("No server certificates provided")
    }
    
    // Case 1: Separate certificates and private keys
    if !securityParameters.serverPrivateKeys.isEmpty {
        // Build certificate chain
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
        
        // Use the first private key
        let keyData = securityParameters.serverPrivateKeys[0]
        
        let privateKey: NIOSSLPrivateKey
        if keyData.starts(with: "-----BEGIN".data(using: .utf8)!) {
            privateKey = try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem)
        } else {
            privateKey = try NIOSSLPrivateKey(bytes: Array(keyData), format: .der)
        }
        
        // Check for encrypted private keys
        if securityParameters.privateKeyPassword != nil {
            throw TransportError.establishmentFailure("Encrypted private keys not yet supported")
        }
        
        let privateKeySource = NIOSSLPrivateKeySource.privateKey(privateKey)
        
        return (certificateChain, privateKeySource)
    }
    
    // Case 2: PKCS#12 format not yet supported
    if let firstCertData = securityParameters.serverCertificates.first {
        do {
            _ = try NIOSSLCertificate(bytes: Array(firstCertData), format: .der)
            throw TransportError.establishmentFailure("Server certificate provided but no private key found. Use serverPrivateKeys or provide PKCS#12 data.")
        } catch {
            throw TransportError.establishmentFailure("PKCS#12 format not yet supported. Please provide separate certificate and private key.")
        }
    }
    
    throw TransportError.establishmentFailure("Unable to extract server credentials")
}