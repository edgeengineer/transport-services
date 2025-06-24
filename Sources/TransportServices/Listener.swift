#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A passive endpoint awaiting incoming Connections from Remote Endpoints.
///
/// A Listener represents a passive open operation as defined in RFC 9622 §7.2.
/// It is created through the `Preconnection.listen()` action and enables servers
/// to accept incoming Connections from clients.
///
/// ## Overview
///
/// Listeners are the server-side abstraction in Transport Services, providing:
/// - Asynchronous delivery of incoming Connections
/// - Rate limiting for connection acceptance
/// - Clean shutdown with the `stop()` method
///
/// Once created, a Listener operates independently of the Preconnection that
/// created it. Changes to the Preconnection after calling `listen()` do not
/// affect existing Listeners.
///
/// ## Connection Delivery
///
/// According to RFC 9622 §7.2, the ConnectionReceived event occurs when:
/// - A Remote Endpoint establishes a transport-layer connection (for connection-oriented protocols)
/// - The first Message is received from a Remote Endpoint (for connectionless protocols)
/// - A new stream is created in a multi-stream transport
///
/// ## Usage Example
///
/// ```swift
/// // Create a server listener
/// let local = LocalEndpoint(kind: .host("0.0.0.0"))
/// local.port = 8080
/// 
/// let preconnection = Preconnection(local: [local])
/// let listener = try await preconnection.listen()
/// 
/// // Accept connections
/// for try await connection in listener.newConnections {
///     Task {
///         // Handle each connection concurrently
///         await handleClient(connection)
///     }
/// }
/// ```
///
/// ## Rate Limiting
///
/// To protect against resource exhaustion, use `setNewConnectionLimit(_:)`:
/// ```swift
/// // Accept at most 10 connections at a time
/// await listener.setNewConnectionLimit(10)
/// 
/// // Process connections and increase limit as needed
/// for try await connection in listener.newConnections {
///     await processConnection(connection)
///     await listener.setNewConnectionLimit(10) // Reset limit
/// }
/// ```
///
/// ## Lifecycle
///
/// 1. **Created**: Via `Preconnection.listen()`
/// 2. **Active**: Accepting connections until stopped
/// 3. **Stopped**: After calling `stop()` or global shutdown
///
/// ## Events
///
/// The Listener can emit several events (via the stream or errors):
/// - **ConnectionReceived**: New Connection ready for use
/// - **EstablishmentError**: Listen operation failed
/// - **Stopped**: Listener has stopped
///
/// ## Topics
///
/// ### Accepting Connections
/// - ``newConnections``
///
/// ### Managing the Listener
/// - ``stop()``
/// - ``setNewConnectionLimit(_:)``
///
/// ## RFC 9622 Compliance
///
/// This implementation follows RFC 9622 §7.2 (Passive Open: Listen):
/// - Requires at least one Local Endpoint on the Preconnection
/// - Delivers Connections via asynchronous events
/// - Supports connection rate limiting
/// - Continues until explicitly stopped or global shutdown
public actor Listener: Sendable {
    
    // MARK: - Properties
    
    /// The internal implementation
    private let impl: ListenerImpl?
    
    /// The stream of incoming connections
    private let stream: AsyncThrowingStream<Connection, Error>?
    
    // MARK: - Initialization
    
    /// Internal initializer
    internal init(impl: ListenerImpl, stream: AsyncThrowingStream<Connection, Error>) {
        self.impl = impl
        self.stream = stream
    }
    
    /// Public initializer for testing
    public init() {
        self.impl = nil
        self.stream = nil
    }
    
    /// An asynchronous stream of incoming Connections.
    ///
    /// Each Connection delivered through this stream is already in the
    /// Established state and ready for immediate use. The Connection has
    /// been fully negotiated with the Remote Endpoint.
    ///
    /// According to RFC 9622 §7.2, Connections are delivered when:
    /// - A transport connection is established (TCP, QUIC)
    /// - The first message arrives (UDP)
    /// - A new stream is created (multi-stream protocols)
    ///
    /// The stream throws errors in these cases:
    /// - **EstablishmentError**: Protocol selection failed, endpoint resolution failed,
    ///   or the application is prohibited from listening
    /// - **Stopped**: The Listener has been stopped
    ///
    /// ## Example
    /// ```swift
    /// do {
    ///     for try await connection in listener.newConnections {
    ///         print("New connection from \(connection.remoteEndpoint)")
    ///         Task { await handleConnection(connection) }
    ///     }
    /// } catch {
    ///     print("Listener error: \(error)")
    /// }
    /// ```
    ///
    /// - Note: The stream completes when the Listener is stopped.
    public nonisolated var newConnections: AsyncThrowingStream<Connection, Error> { 
        stream ?? AsyncThrowingStream { _ in }
    }
    
    // MARK: - Methods
    
    /// Stops accepting new Connections and closes the Listener.
    ///
    /// After calling this method:
    /// - No new Connections will be delivered
    /// - The `newConnections` stream will complete
    /// - A Stopped event is generated
    /// - Existing Connections remain unaffected
    ///
    /// According to RFC 9622 §7.2, listening continues until either:
    /// - The Stop action is performed
    /// - The global context shuts down
    ///
    /// - Note: This operation is idempotent; calling stop() multiple times
    ///   has no additional effect.
    public func stop() async {
        await impl?.stop()
    }
    
    /// Sets a limit on the number of Connections that will be delivered.
    ///
    /// This mechanism provides protection against resource exhaustion by
    /// rate-limiting Connection acceptance. Each ConnectionReceived event
    /// automatically decrements this value.
    ///
    /// - Parameter limit: Maximum number of Connections to deliver.
    ///   - Pass a positive number to set a specific limit
    ///   - Pass `nil` to set the limit to infinite (default)
    ///   - When the limit reaches 0, no Connections are delivered
    ///
    /// According to RFC 9622 §7.2, this allows servers to protect themselves
    /// from being drained of resources during high load or attacks.
    ///
    /// ## Usage Pattern
    /// ```swift
    /// // Set initial limit
    /// await listener.setNewConnectionLimit(100)
    /// 
    /// // Process connections in batches
    /// for try await connection in listener.newConnections {
    ///     connectionCount += 1
    ///     
    ///     // Refresh limit periodically
    ///     if connectionCount % 10 == 0 {
    ///         await listener.setNewConnectionLimit(100)
    ///     }
    /// }
    /// ```
    ///
    /// - Note: The limit only affects new Connection delivery. Existing
    ///   Connections and those already in the delivery queue are unaffected.
    public func setNewConnectionLimit(_ limit: Int?) async {
        await impl?.setConnectionLimit(limit)
    }
}

// MARK: - CustomStringConvertible

extension Listener: CustomStringConvertible {
    nonisolated public var description: String {
        "Listener(active)"
    }
}