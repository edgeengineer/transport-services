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
            
            listeners.append(channel)
            
        } catch {
            // Continue with other endpoints on error
        }
    }
    
    /// Creates a child channel initializer
    private func makeChildChannelInitializer() -> @Sendable (Channel) -> EventLoopFuture<Void> {
        let framers = self.framers
        let securityParams = self.securityParameters
        let weakSelf = self
        
        return { @Sendable channel in
            Self.configureIncomingChannel(
                channel: channel,
                framers: framers,
                securityParameters: securityParams,
                impl: weakSelf
            )
        }
    }
    
    /// Configures an incoming channel
    private static func configureIncomingChannel(channel: Channel,
                                                  framers: [any MessageFramer],
                                                  securityParameters: SecurityParameters,
                                                  impl: RendezvousImpl) -> EventLoopFuture<Void> {
        // Similar configuration to outgoing connections
        var handlers: [ChannelHandler] = []
        
        // Add TLS if required
        if !securityParameters.allowedProtocols.isEmpty {
            do {
                let tlsConfiguration = TLSConfiguration.makeServerConfiguration(
                    certificateChain: [], // Would need actual certificates
                    privateKey: .privateKey(try .init(bytes: [], format: .der)) // Would need actual key
                )
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let tlsHandler = NIOSSLServerHandler(context: sslContext)
                handlers.append(tlsHandler)
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
        
        // Add message framing
        handlers.append(MessageFramingHandler(framers: framers))
        
        // Add rendezvous handler
        handlers.append(RendezvousIncomingHandler(impl: impl))
        
        var future = channel.eventLoop.makeSucceededFuture(())
        for handler in handlers {
            future = future.flatMap { channel.pipeline.addHandler(handler) }
        }
        return future
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
        do {
            let impl = ConnectionImpl(
                id: UUID(),
                properties: properties,
                securityParameters: securityParameters,
                framers: framers,
                eventLoopGroup: eventLoopGroup
            )
            
            try await impl.establish(to: remoteEndpoint, from: localEndpoint)
            
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
                completionHandler?.resume(throwing: TransportError.establishmentFailure(
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
        
        let bridge = ConnectionBridge(impl: impl)
        let connection = Connection()
        await connection.setBridge(bridge)
        
        await handleSuccessfulConnection(connection)
    }
    
    /// Handles the first successful connection
    private func handleSuccessfulConnection(_ connection: Connection) async {
        guard establishedConnection == nil else { return }
        
        establishedConnection = connection
        
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
        
        // Complete the rendezvous
        completionHandler?.resume(returning: connection)
    }
}

// MARK: - Channel Handlers

/// Handles incoming connections during rendezvous
private final class RendezvousIncomingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    
    private let impl: RendezvousImpl
    
    init(impl: RendezvousImpl) {
        self.impl = impl
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // New incoming connection established
        let channel = context.channel
        
        Task {
            await impl.handleIncomingConnection(channel)
        }
    }
}

// MARK: - Message Framing Handler (reused from ConnectionImpl)

/// Handles message framing for the connection
private final class MessageFramingHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Message
    typealias OutboundIn = Message
    typealias OutboundOut = ByteBuffer
    
    private let framers: [any MessageFramer]
    
    init(framers: [any MessageFramer]) {
        self.framers = framers
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        
        // For now, treat the entire buffer as a message
        // Full implementation would use framers to delimit messages
        let message = Message(Data(buffer.readableBytesView))
        
        context.fireChannelRead(wrapInboundOut(message))
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        
        var buffer = context.channel.allocator.buffer(capacity: message.data.count)
        buffer.writeBytes(message.data)
        
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
}