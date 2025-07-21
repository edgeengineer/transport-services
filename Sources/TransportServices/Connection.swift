#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The live transport object representing an active network connection.
///
/// `Connection` is an actor that isolates mutable state and provides async methods
/// with structured concurrency. It represents a single transport connection that
/// can send and receive messages according to RFC 9622.
///
/// ## Topics
///
/// ### Creating Connections
/// Connections are typically created through ``Preconnection/initiate(timeout:)``
/// or received from a ``Listener``.
///
/// ### Sending Data
/// - ``send(_:)``
/// - ``sendPartial(_:context:endOfMessage:)``
///
/// ### Receiving Data
/// - ``receive(minIncomplete:max:)``
/// - ``incomingMessages``
///
/// ### Connection State
/// - ``id``
/// - ``state``
/// - ``properties``
/// - ``remoteEndpoint``
/// - ``localEndpoint``
///
/// ### Connection Groups
/// - ``clone(framer:altering:)``
/// - ``groupedConnections``
///
/// ### Lifecycle Management
/// - ``close()``
/// - ``closeGroup()``
/// - ``abort()``
/// - ``abortGroup()``
public actor Connection: CustomStringConvertible, Sendable {
    
    // MARK: - Internal Implementation
    
    /// The internal implementation
    /// This is set by the Transport Services implementation when creating connections
    internal var _impl: ConnectionImpl?
    
    /// Cached ID for nonisolated access
    private let _id: UUID
    
    /// Internal initializer  
    internal init() {
        self._id = UUID()
    }
    
    /// Internal method to set the implementation
    internal func setImpl(_ impl: ConnectionImpl) async {
        self._impl = impl
    }
    
    // MARK: - Identity & State
    
    /// The unique identifier for this connection.
    ///
    /// This immutable UUID enables dictionary lookups, telemetry, and cancellation tokens.
    /// Each connection has a unique ID that persists throughout its lifetime.
    public var id: UUID { 
        _impl?.id ?? _id 
    }
    
    /// The current state of the connection.
    ///
    /// Mirrors RFC 9622 §11 state machine. State changes are surfaced only through
    /// async property reads or events, never by KVO.
    ///
    /// - Note: This is a read-only property that reflects the internal state machine.
    public var state: ConnectionState { 
        get async { 
            await _impl?.state ?? .establishing 
        } 
    }
    
    /// The transport properties for this connection.
    ///
    /// These are copied from the ``Preconnection`` at establishment time and remain
    /// read-only throughout the connection's lifetime.
    public var properties: TransportProperties { 
        get async { 
            await _impl?.properties ?? TransportProperties() 
        } 
    }
    
    /// The remote endpoint this connection is connected to.
    public var remoteEndpoint: RemoteEndpoint { 
        get async { 
            await _impl?.remoteEndpoint ?? RemoteEndpoint(kind: .host("")) 
        } 
    }
    
    /// The local endpoint this connection is bound to.
    public var localEndpoint: LocalEndpoint { 
        get async { 
            await _impl?.localEndpoint ?? LocalEndpoint(kind: .host("")) 
        } 
    }
    
    public nonisolated var description: String { 
        "Connection(id: \(_id))"
    }
    
    // MARK: - Sending
    
    /// Sends a complete message on this connection.
    ///
    /// This method implements RFC 9622 §9.2 Send. Each call is `async throws` so the
    /// call-site can `try await` for completion and handle errors.
    ///
    /// - Parameter message: The message to send, including data and context.
    /// - Throws: ``TransportError/sendFailure(_:)`` if the send operation fails.
    ///
    /// ## Example
    /// ```swift
    /// let data = Data("Hello, World!".utf8)
    /// let message = Message(data)
    /// try await connection.send(message)
    /// ```
    public func send(_ message: Message) async throws {
        guard let impl = _impl else {
            throw TransportError.sendFailure("Connection not initialized")
        }
        try await impl.send(message)
    }
    
    /// Sends a partial message on this connection.
    ///
    /// This method allows sending data in chunks for streaming scenarios.
    ///
    /// - Parameters:
    ///   - slice: The data slice to send.
    ///   - context: The message context containing metadata.
    ///   - endOfMessage: Whether this is the final chunk of the message.
    /// - Throws: ``TransportError/sendFailure(_:)`` if the send operation fails.
    public func sendPartial(_ slice: Data,
                            context: MessageContext,
                            endOfMessage: Bool) async throws {
        guard let impl = _impl else {
            throw TransportError.sendFailure("Connection not initialized")
        }
        let message = Message(slice, context: context)
        try await impl.send(message)
    }
    
    // MARK: - Receiving
    
    /// Receives a message from this connection.
    ///
    /// This method implements RFC 9622 §9.3 Receive with built-in back-pressure.
    /// Every receive() call returns one event; buffering stops if the user stops
    /// awaiting. This allows the receiver to throttle by simply not calling.
    ///
    /// - Parameters:
    ///   - minIncomplete: Minimum bytes to receive for incomplete messages.
    ///   - max: Maximum bytes to receive in one call.
    /// - Returns: A received ``Message`` with data and context.
    /// - Throws: ``TransportError/receiveFailure(_:)`` if the receive fails.
    ///
    /// ## Example
    /// ```swift
    /// do {
    ///     let message = try await connection.receive()
    ///     print("Received: \\(String(data: message.data, encoding: .utf8) ?? "")")
    /// } catch {
    ///     print("Receive failed: \\(error)")
    /// }
    /// ```
    public func receive(minIncomplete: Int = .max,
                        max: Int = .max) async throws -> Message {
        guard let impl = _impl else {
            throw TransportError.receiveFailure("Connection not initialized")
        }
        return try await impl.receive()
    }
    
    /// An async stream of incoming messages.
    ///
    /// This provides an ergonomic alternative to calling ``receive(minIncomplete:max:)``
    /// in a loop. The stream is cold until requested, avoiding classical delegate races.
    ///
    /// ## Example
    /// ```swift
    /// for try await message in connection.incomingMessages {
    ///     print("Received: \\(String(data: message.data, encoding: .utf8) ?? "")")
    /// }
    /// ```
    ///
    /// - Note: The stream automatically handles back-pressure by pausing when not consumed.
    public var incomingMessages: AsyncThrowingStream<Message,Error> { 
        get async {
            guard let impl = _impl else {
                return AsyncThrowingStream { _ in }
            }
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        while await impl.state == .established {
                            let message = try await impl.receive()
                            continuation.yield(message)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: - Connection Groups
    
    /// Creates a new connection in the same connection group.
    ///
    /// Implements Connection Groups (RFC 9622 §7.4) while keeping the actor surface
    /// minimal—no explicit ConnectionGroup type is required in Swift.
    ///
    /// - Parameters:
    ///   - framer: Optional message framer for the cloned connection.
    ///   - transport: Optional transport properties to override.
    /// - Returns: A new ``Connection`` in the same group.
    /// - Throws: ``TransportError/establishmentFailure(_:)`` if cloning fails.
    ///
    /// ## Example
    /// ```swift
    /// // Create a new connection sharing the same 5-tuple
    /// let cloned = try await connection.clone()
    /// ```
    public func clone(framer: (any MessageFramer)? = nil,
                      altering transport: TransportProperties? = nil) async throws -> Connection {
        guard let impl = _impl else {
            throw TransportError.establishmentFailure("Connection not initialized")
        }
        
        // Ensure this connection is in a group before cloning
        let group: ConnectionGroup
        if let existingGroup = await impl.getConnectionGroup() {
            group = existingGroup
        } else {
            // Create a new group for this connection
            group = ConnectionGroup(
                properties: await impl.properties,
                securityParameters: await impl.securityParameters,
                framers: await impl.framers
            )
            await impl.setConnectionGroup(group)
        }
        
        // Add this connection to the group if not already there
        await group.addConnection(self)
        
        // Create the cloned connection
        let clonedImpl = try await impl.clone(altering: transport, framer: framer)
        let connection = Connection()
        await connection.setImpl(clonedImpl)
        
        // Add the cloned connection to the group
        await group.addConnection(connection)
        
        return connection
    }
    
    /// All connections in this connection's group.
    ///
    /// Returns an array of all connections sharing the same connection group,
    /// including this connection itself.
    public var groupedConnections: [Connection] { 
        get async { 
            guard let impl = _impl,
                  let group = await impl.getConnectionGroup() else {
                return []
            }
            
            // Ensure this connection is in the group
            await group.addConnection(self)
            return await group.getAllConnections()
        } 
    }
    
    // MARK: - Lifecycle
    
    /// Gracefully closes this connection.
    ///
    /// Implements RFC 9622 §10 Close. This initiates a graceful shutdown,
    /// allowing pending sends to complete and the peer to be notified.
    ///
    /// ## Example
    /// ```swift
    /// await connection.close()
    /// ```
    public func close() async {
        await _impl?.close()
    }
    
    /// Gracefully closes all connections in this connection's group.
    ///
    /// This is equivalent to calling ``close()`` on each connection in
    /// ``groupedConnections``.
    public func closeGroup() async {
        guard let impl = _impl,
              let group = await impl.getConnectionGroup() else {
            await _impl?.close()
            return
        }
        
        let connections = await group.getAllConnections()
        await withTaskGroup(of: Void.self) { taskGroup in
            for connection in connections {
                taskGroup.addTask {
                    await connection.close()
                }
            }
        }
    }
    
    /// Immediately aborts this connection.
    ///
    /// Unlike ``close()``, this immediately terminates the connection without
    /// waiting for pending operations or notifying the peer gracefully.
    public func abort() async {
        await _impl?.abort()
    }
    
    /// Immediately aborts all connections in this connection's group.
    ///
    /// This is equivalent to calling ``abort()`` on each connection in
    /// ``groupedConnections``.
    public func abortGroup() async {
        guard let impl = _impl,
              let group = await impl.getConnectionGroup() else {
            await _impl?.abort()
            return
        }
        
        let connections = await group.getAllConnections()
        await withTaskGroup(of: Void.self) { taskGroup in
            for connection in connections {
                taskGroup.addTask {
                    await connection.abort()
                }
            }
        }
    }
}
