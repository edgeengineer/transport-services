#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore
import NIOPosix

/// Implementation of multicast connections.
///
/// This class handles multicast group management and implements the
/// specific behaviors required for multicast as per RFC 9622.
actor MulticastConnectionImpl {
    
    // MARK: - Properties
    
    private let multicastEndpoint: MulticastEndpoint
    private let properties: TransportProperties
    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel?
    private var connectionGroup: ConnectionGroup?
    
    /// Tracks unique senders for receiver connections
    private var activeSenders: [SocketAddress: Connection] = [:]
    
    // MARK: - Initialization
    
    init(multicastEndpoint: MulticastEndpoint,
         properties: TransportProperties,
         eventLoopGroup: EventLoopGroup) {
        self.multicastEndpoint = multicastEndpoint
        self.properties = properties
        self.eventLoopGroup = eventLoopGroup
    }
    
    // MARK: - Multicast Operations
    
    /// Establishes a multicast sender connection
    func establishSender() async throws -> Connection {
        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                // Capture self for async context
                let capturedSelf = self
                return capturedSelf.configureSenderChannel(channel: channel)
            }
        
        // Bind to ephemeral port for sending
        let channel = try await bootstrap.bind(host: "0.0.0.0", port: 0).get()
        self.channel = channel
        
        // Configure multicast options
        try await configureMulticastOptions(channel: channel, forSending: true)
        
        // Create connection wrapper
        let impl = ConnectionImpl(
            id: UUID(),
            properties: properties,
            securityParameters: SecurityParameters(),
            framers: [],
            eventLoopGroup: eventLoopGroup
        )
        
        await impl.setEstablishedChannel(channel)
        
        let bridge = ConnectionBridge(impl: impl)
        let connection = Connection()
        await connection.setBridge(bridge)
        
        return connection
    }
    
    /// Establishes a multicast receiver listener
    func establishReceiver() async throws -> MulticastListener {
        // Create a connection group for all senders
        let group = ConnectionGroup(
            properties: properties,
            securityParameters: SecurityParameters(),
            framers: []
        )
        self.connectionGroup = group
        
        // Create the listener first so we can pass it to the handler
        let listener = MulticastListener(impl: self, group: group)
        
        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            // Note: SO_REUSEPORT is platform-specific and not available in NIO directly
            .channelInitializer { channel in
                let capturedSelf = self
                let capturedListener = listener
                return capturedSelf.configureReceiverChannel(channel: channel, listener: capturedListener)
            }
        
        // Bind to the multicast port
        let channel = try await bootstrap.bind(
            host: "0.0.0.0", // Bind to any address
            port: Int(multicastEndpoint.port)
        ).get()
        
        self.channel = channel
        
        // Join the multicast group
        try await joinMulticastGroup(channel: channel)
        
        // Configure multicast options
        try await configureMulticastOptions(channel: channel, forSending: false)
        
        return listener
    }
    
    /// Configures multicast options on the channel
    private func configureMulticastOptions(channel: Channel, forSending: Bool) async throws {
        // Note: Multicast options are typically set via socket options
        // SwiftNIO doesn't have direct multicast support yet, so we'd need to:
        // 1. Access the underlying socket
        // 2. Set options using system calls
        // For now, this is a placeholder implementation
        
        // TODO: Implement proper multicast socket options when NIO adds support
        // or use raw socket options
    }
    
    /// Joins a multicast group
    private func joinMulticastGroup(channel: Channel) async throws {
        // This would use IP_ADD_MEMBERSHIP or IPV6_JOIN_GROUP
        // Implementation depends on whether it's IPv4 or IPv6
        
        switch multicastEndpoint.type {
        case .anySource:
            // Join for any source
            print("Joining ASM group \(multicastEndpoint.groupAddress)")
        case .sourceSpecific(let sources):
            // Join with source filter (IP_ADD_SOURCE_MEMBERSHIP)
            print("Joining SSM group \(multicastEndpoint.groupAddress) from sources: \(sources)")
        }
    }
    
    /// Handles a datagram from a new sender
    func handleDatagramFromSender(_ data: ByteBuffer, sender: SocketAddress, listener: MulticastListener?) async -> Connection? {
        // Check if we already have a connection for this sender
        if let existingConnection = activeSenders[sender] {
            return existingConnection
        }
        
        // Create a new connection for this sender
        guard let group = connectionGroup else { return nil }
        
        let impl = ConnectionImpl(
            id: UUID(),
            properties: await group.getSharedProperties(),
            securityParameters: await group.getSecurityParameters(),
            framers: await group.getFramers(),
            eventLoopGroup: eventLoopGroup
        )
        
        // Set connection as established with sender info
        await impl.setEstablishedChannel(channel!) // Use the shared channel
        
        let bridge = ConnectionBridge(impl: impl)
        let connection = Connection()
        await connection.setBridge(bridge)
        
        // Add to group
        await group.addConnection(connection)
        await impl.setConnectionGroup(group)
        
        // Track this sender
        activeSenders[sender] = connection
        
        // Notify the listener about the new connection
        if let listener = listener {
            await listener.handleNewSender(connection)
        }
        
        return connection
    }
    
    /// Stops the multicast connection
    func stop() async {
        // Leave multicast group
        if let channel = channel {
            try? await channel.close()
        }
        
        // Clear active senders
        activeSenders.removeAll()
    }
    
    // MARK: - Channel Configuration
    
    nonisolated private func configureSenderChannel(channel: Channel) -> EventLoopFuture<Void> {
        // Add handler for sending to multicast group
        return channel.pipeline.addHandler(MulticastSenderHandler(
            multicastEndpoint: multicastEndpoint
        ))
    }
    
    nonisolated private func configureReceiverChannel(channel: Channel, listener: MulticastListener) -> EventLoopFuture<Void> {
        // Add handler for receiving from multicast group
        return channel.pipeline.addHandler(MulticastReceiverHandler(
            impl: self,
            listener: listener
        ))
    }
}

// MARK: - Multicast Listener

/// A listener that creates connections for each unique multicast sender
public actor MulticastListener {
    private let impl: MulticastConnectionImpl
    private let group: ConnectionGroup
    private var connectionContinuation: AsyncThrowingStream<Connection, Error>.Continuation?
    private var isActive = true
    
    init(impl: MulticastConnectionImpl, group: ConnectionGroup) {
        self.impl = impl
        self.group = group
    }
    
    public var newConnections: AsyncThrowingStream<Connection, Error> {
        AsyncThrowingStream { continuation in
            self.connectionContinuation = continuation
            
            // Set up cleanup when stream is terminated
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.stop()
                }
            }
        }
    }
    
    public func stop() async {
        guard isActive else { return }
        isActive = false
        
        // Finish the stream
        connectionContinuation?.finish()
        connectionContinuation = nil
        
        // Stop the multicast implementation
        await impl.stop()
    }
    
    public func setNewConnectionLimit(_ limit: Int?) async {
        // Could implement by tracking active senders count
        // and rejecting new ones when limit is reached
    }
    
    /// Called by MulticastConnectionImpl when a new sender is detected
    func handleNewSender(_ connection: Connection) {
        guard isActive else { return }
        connectionContinuation?.yield(connection)
    }
}

// MARK: - Channel Handlers

/// Handles sending to a multicast group
private final class MulticastSenderHandler: ChannelOutboundHandler, @unchecked Sendable {
    typealias OutboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    private let multicastEndpoint: MulticastEndpoint
    private let multicastAddress: SocketAddress?
    
    init(multicastEndpoint: MulticastEndpoint) {
        self.multicastEndpoint = multicastEndpoint
        
        // Create socket address for the multicast group
        do {
            self.multicastAddress = try SocketAddress(
                ipAddress: multicastEndpoint.groupAddress,
                port: Int(multicastEndpoint.port)
            )
        } catch {
            self.multicastAddress = nil
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let envelope = unwrapOutboundIn(data)
        
        // Always send to the multicast address
        if let multicastAddress = multicastAddress {
            let newEnvelope = AddressedEnvelope(
                remoteAddress: multicastAddress,
                data: envelope.data
            )
            context.write(wrapOutboundOut(newEnvelope), promise: promise)
        } else {
            promise?.fail(TransportError.sendFailure("Invalid multicast address"))
        }
    }
}

/// Handles receiving from a multicast group
private final class MulticastReceiverHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    
    private let impl: MulticastConnectionImpl
    private let listener: MulticastListener
    
    init(impl: MulticastConnectionImpl, listener: MulticastListener) {
        self.impl = impl
        self.listener = listener
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        
        Task {
            // Create or get connection for this sender
            if let connection = await impl.handleDatagramFromSender(
                envelope.data,
                sender: envelope.remoteAddress,
                listener: listener
            ) {
                // Deliver the data to the connection
                // This would need to be integrated with the connection's receive mechanism
            }
        }
    }
}

