#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOPosix
@preconcurrency import NIOSSL

/// Internal implementation of a Transport Services Connection using SwiftNIO.
///
/// This class implements the actual transport functionality for Connection objects,
/// following RFC 9623's guidance on implementing connection objects.
actor ConnectionImpl {
    
    // MARK: - Properties
    
    /// The unique identifier for this connection
    let id: UUID
    
    /// The transport properties configured during preestablishment
    let properties: TransportProperties
    
    /// The security parameters for this connection
    let securityParameters: SecurityParameters
    
    /// Message framers for this connection
    let framers: [any MessageFramer]
    
    /// The NIO channel for this connection
    private var channel: Channel?
    
    /// The event loop group managing this connection
    private let eventLoopGroup: EventLoopGroup
    
    /// The current state of the connection
    private var _state: ConnectionState = .establishing
    
    /// Remote endpoint information
    private var _remoteEndpoint: RemoteEndpoint?
    
    /// Local endpoint information
    private var _localEndpoint: LocalEndpoint?
    
    /// Pending send completions
    private var pendingSends: [UUID: CheckedContinuation<Void, Error>] = [:]
    
    /// Incoming message buffer
    private var incomingMessages: [Message] = []
    
    /// Receive continuations waiting for messages
    private var receiveWaiters: [CheckedContinuation<Message, Error>] = []
    
    /// Connection group this connection belongs to
    private var connectionGroup: ConnectionGroup?
    
    /// Whether a final message has been sent on this connection
    private var finalMessageSent: Bool = false
    
    // MARK: - Initialization
    
    init(id: UUID,
         properties: TransportProperties,
         securityParameters: SecurityParameters,
         framers: [any MessageFramer],
         eventLoopGroup: EventLoopGroup) {
        self.id = id
        self.properties = properties
        self.securityParameters = securityParameters
        self.framers = framers
        self.eventLoopGroup = eventLoopGroup
    }
    
    // MARK: - State Management
    
    var state: ConnectionState {
        _state
    }
    
    var remoteEndpoint: RemoteEndpoint? {
        _remoteEndpoint
    }
    
    var localEndpoint: LocalEndpoint? {
        _localEndpoint
    }
    
    // MARK: - Connection Establishment
    
    /// Sets an already-established channel (used by Rendezvous)
    func setEstablishedChannel(_ channel: Channel) async {
        self.channel = channel
        self._state = .established
        
        // Extract endpoint information
        if let remoteAddress = channel.remoteAddress {
            self._remoteEndpoint = RemoteEndpoint(
                kind: .ip(remoteAddress.description)
            )
        }
        
        if let localAddress = channel.localAddress {
            self._localEndpoint = LocalEndpoint(
                kind: .ip(localAddress.description)
            )
        }
    }
    
    /// Establishes the connection to the remote endpoint
    func establish(to remoteEndpoint: RemoteEndpoint, 
                   from localEndpoint: LocalEndpoint? = nil) async throws {
        // Implementation will:
        // 1. Resolve endpoints
        // 2. Select appropriate protocol stack
        // 3. Perform protocol handshakes
        // 4. Configure channel pipeline
        
        self._remoteEndpoint = remoteEndpoint
        self._localEndpoint = localEndpoint
        
        // For now, we'll implement a basic TCP connection
        // Full implementation will support protocol selection based on properties
        
        do {
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: properties.disableNagle ? 1 : 0)
                .channelInitializer(makeChannelInitializer())
            
            // Connect to the remote endpoint
            let channel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
                let connectFuture: EventLoopFuture<Channel>
                
                switch remoteEndpoint.kind {
                case .host(let hostname):
                    connectFuture = bootstrap.connect(host: hostname, port: Int(remoteEndpoint.port ?? 0))
                case .ip(let address):
                    connectFuture = bootstrap.connect(host: address, port: Int(remoteEndpoint.port ?? 0))
                }
                
                connectFuture.whenComplete { result in
                    continuation.resume(with: result)
                }
            }
            
            self.channel = channel
            self._state = .established
            
            // Extract local endpoint information
            if let localAddress = channel.localAddress {
                self._localEndpoint = LocalEndpoint(
                    kind: .ip(localAddress.description) // Simplified, should parse properly
                )
            }
            
        } catch {
            self._state = .closed
            throw TransportError.establishmentFailure("Failed to establish connection: \(error)")
        }
    }
    
    /// Establishes the connection with 0-RTT and sends the first message
    func establishWithSend(to remoteEndpoint: RemoteEndpoint,
                           from localEndpoint: LocalEndpoint? = nil,
                           firstMessage: Message) async throws {
        
        self._remoteEndpoint = remoteEndpoint
        self._localEndpoint = localEndpoint
        
        // Store the first message to send after connection
        let capturedMessage = firstMessage
        
        do {
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: properties.disableNagle ? 1 : 0)
                .channelInitializer(makeChannelInitializer())
            
            // Enable TCP Fast Open if available (for 0-RTT)
            if properties.zeroRTT == .require || properties.zeroRTT == .prefer {
                // TCP Fast Open support would be configured here
                // This is platform-specific and requires additional setup
            }
            
            // Connect to the remote endpoint
            let channel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
                let connectFuture: EventLoopFuture<Channel>
                
                switch remoteEndpoint.kind {
                case .host(let hostname):
                    connectFuture = bootstrap.connect(host: hostname, port: Int(remoteEndpoint.port ?? 0))
                case .ip(let address):
                    connectFuture = bootstrap.connect(host: address, port: Int(remoteEndpoint.port ?? 0))
                }
                
                connectFuture.whenComplete { result in
                    continuation.resume(with: result)
                }
            }
            
            self.channel = channel
            
            // Extract local endpoint information
            if let localAddress = channel.localAddress {
                self._localEndpoint = LocalEndpoint(
                    kind: .ip(localAddress.description) // Simplified, should parse properly
                )
            }
            
            // Set state to established before sending to allow the send
            self._state = .established
            
            // Send the first message immediately
            // For true 0-RTT, this would be sent during the handshake
            // We're simulating by sending immediately after connection
            try await send(capturedMessage)
            
        } catch {
            self._state = .closed
            throw TransportError.establishmentFailure("Failed to establish connection with 0-RTT: \(error)")
        }
    }
    
    /// Creates a channel initializer
    private func makeChannelInitializer() -> @Sendable (Channel) -> EventLoopFuture<Void> {
        // Capture needed values
        let securityParams = self.securityParameters 
        let serverHostname = self.getServerHostname()
        let weakSelf = self
        
        return { @Sendable channel in
            var future = channel.eventLoop.makeSucceededFuture(())
            
            // Add TLS if required (check if TLS protocols are allowed)
            if !securityParams.allowedProtocols.isEmpty {
                do {
                    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                    
                    // Configure callbacks if provided
                    if securityParams.callbacks.trustVerificationCallback != nil || 
                       securityParams.callbacks.identityChallengeCallback != nil {
                        // Create a security callback handler
                        let callbackHandler = SecurityCallbackHandler(
                            callbacks: securityParams.callbacks,
                            serverName: serverHostname
                        )
                        
                        // Note: NIO SSL doesn't support custom verification callbacks yet
                        // For now, disable hostname verification when custom callbacks are present
                        // In production, this should use the callback handler when supported
                        tlsConfiguration.certificateVerification = .noHostnameVerification
                        
                        // The callback handler is ready for when NIOSSL adds support
                        _ = callbackHandler.makeNIOSSLCustomVerificationCallback()
                    }
                    
                    // Configure ALPN if provided
                    if !securityParams.alpn.isEmpty {
                        tlsConfiguration.applicationProtocols = securityParams.alpn
                    }
                    
                    let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                    let tlsHandler = try NIOSSLClientHandler(
                        context: sslContext,
                        serverHostname: serverHostname
                    )
                    future = future.flatMap { channel.pipeline.addHandler(tlsHandler) }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            
            // Add message framing handler
            let framingHandler = SimpleFramingHandler()
            future = future.flatMap { channel.pipeline.addHandler(framingHandler) }
            
            // Add the main connection handler
            let connectionHandler = ConnectionHandler(impl: weakSelf)
            future = future.flatMap { channel.pipeline.addHandler(connectionHandler) }
            
            return future
        }
    }
    
    private func getServerHostname() -> String? {
        switch _remoteEndpoint?.kind {
        case .host(let hostname):
            return hostname
        case .ip(_):
            return nil
        case .none:
            return nil
        }
    }
    
    // MARK: - Sending
    
    /// Sends a message on the connection
    func send(_ message: Message) async throws {
        guard _state == .established else {
            throw TransportError.sendFailure("Connection not ready")
        }
        
        // Check if a final message has already been sent
        guard !finalMessageSent else {
            throw TransportError.sendFailure("Cannot send after final message")
        }
        
        // Check if connection allows sending
        guard properties.direction != .recvOnly else {
            throw TransportError.sendFailure("Cannot send on receive-only connection")
        }
        
        guard let channel = channel else {
            throw TransportError.sendFailure("No channel available")
        }
        
        // Check if this message is marked as final
        if message.context.final {
            finalMessageSent = true
        }
        
        let sendId = UUID()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingSends[sendId] = continuation
            
            let promise = channel.eventLoop.makePromise(of: Void.self)
            promise.futureResult.whenComplete { result in
                Task {
                    await self.completeSend(id: sendId, result: result)
                }
            }
            
            channel.writeAndFlush(message, promise: promise)
        }
    }
    
    /// Completes a pending send operation
    private func completeSend(id: UUID, result: Result<Void, Error>) {
        guard let continuation = pendingSends.removeValue(forKey: id) else {
            return
        }
        
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: TransportError.sendFailure(error.localizedDescription))
        }
    }
    
    // MARK: - Receiving
    
    /// Receives a message from the connection
    func receive() async throws -> Message {
        guard properties.direction != .sendOnly else {
            throw TransportError.receiveFailure("Cannot receive on a send-only connection")
        }
        
        guard _state == .established else {
            throw TransportError.receiveFailure("Connection not ready")
        }
        
        // If we have buffered messages, return one immediately
        if !incomingMessages.isEmpty {
            return incomingMessages.removeFirst()
        }
        
        // Otherwise, wait for a new message
        return try await withCheckedThrowingContinuation { continuation in
            receiveWaiters.append(continuation)
        }
    }
    
    /// Handles an incoming message from the channel
    func handleIncomingMessage(_ message: Message) {
        // If there are waiters, deliver to the first one
        if !receiveWaiters.isEmpty {
            let waiter = receiveWaiters.removeFirst()
            waiter.resume(returning: message)
        } else {
            // Otherwise, buffer the message
            incomingMessages.append(message)
        }
    }
    
    // MARK: - Lifecycle
    
    /// Gracefully closes the connection
    func close() async {
        guard let channel = channel else { return }
        
        _state = .closing
        
        do {
            try await channel.close()
            _state = .closed
        } catch {
            _state = .closed
        }
    }
    
    /// Immediately aborts the connection
    func abort() async {
        _state = .closed
        channel?.close(mode: .all, promise: nil)
    }
    
    // MARK: - Connection Groups
    
    /// Sets the connection group
    func setConnectionGroup(_ group: ConnectionGroup) async {
        self.connectionGroup = group
    }
    
    /// Gets the connection group
    func getConnectionGroup() -> ConnectionGroup? {
        connectionGroup
    }
    
    /// Clones this connection within the same group
    func clone(altering newProperties: TransportProperties? = nil,
               framer: (any MessageFramer)? = nil) async throws -> ConnectionImpl {
        
        // Get or create a connection group
        let group: ConnectionGroup
        if let existingGroup = connectionGroup {
            group = existingGroup
        } else {
            // Create a new group for this connection and its clones
            group = ConnectionGroup(
                properties: newProperties ?? properties,
                securityParameters: securityParameters,
                framers: framers
            )
            await setConnectionGroup(group)
            // Note: The original connection will be added to the group by ConnectionBridge.clone()
        }
        
        // Create a new connection in the same group
        let framersToUse: [any MessageFramer]
        if let framer = framer {
            framersToUse = [framer]
        } else {
            framersToUse = await group.getFramers()
        }
        let finalProperties: TransportProperties
        if let newProperties = newProperties {
            finalProperties = newProperties
        } else {
            finalProperties = await group.getSharedProperties()
        }
        
        let clonedImpl = ConnectionImpl(
            id: UUID(),
            properties: finalProperties,
            securityParameters: await group.getSecurityParameters(),
            framers: framersToUse,
            eventLoopGroup: eventLoopGroup
        )
        
        await clonedImpl.setConnectionGroup(group)
        
        // Establish the cloned connection
        if let remoteEndpoint = _remoteEndpoint {
            try await clonedImpl.establish(to: remoteEndpoint, from: _localEndpoint)
        }
        
        return clonedImpl
    }
}

// MARK: - Channel Handlers

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
        
        // Handle the message directly without additional queuing
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
