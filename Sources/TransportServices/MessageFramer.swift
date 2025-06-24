#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Protocol for implementing Message boundary preservation on byte-stream transports.
///
/// MessageFramer extends a Connection's protocol stack to define how to encode
/// outbound Messages and decode inbound data, as specified in RFC 9622 §9.1.2.
/// This enables Message-oriented communication over transports that don't
/// naturally preserve boundaries (like TCP).
///
/// ## Overview
///
/// Message Framers solve a fundamental problem: many application protocols
/// require message boundaries, but TCP only provides a byte stream. Each
/// application protocol (HTTP, WebSocket, etc.) has historically implemented
/// its own framing. This protocol standardizes that pattern.
///
/// ## Architecture
///
/// According to RFC 9622, Framers sit between the application and transport:
///
/// ```
///     Application
///          |
///     Connection
///          |
///     Framer(s)     ← Message boundaries added/removed here
///          |
///  Transport Protocol
/// ```
///
/// ## Implementation Requirements
///
/// Framers must:
/// 1. Be added during preestablishment (before any Connection is created)
/// 2. Maintain per-Connection state for parsing
/// 3. Handle partial message data across multiple receives
/// 4. Support both stream and datagram transports
///
/// ## Usage Example
///
/// ```swift
/// // Define a simple length-prefixed framer
/// struct LengthPrefixFramer: MessageFramer {
///     func frameOutbound(_ message: Message) async throws -> [Data] {
///         var frame = Data()
///         frame.append(contentsOf: withUnsafeBytes(of: UInt32(message.data.count)) {
///             Data($0)
///         })
///         frame.append(message.data)
///         return [frame]
///     }
///     
///     func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
///         var messages: [Message] = []
///         var buffer = bytes
///         
///         while buffer.count >= 4 {
///             let length = buffer.prefix(4).withUnsafeBytes { 
///                 $0.load(as: UInt32.self) 
///             }
///             
///             guard buffer.count >= 4 + length else { break }
///             
///             let messageData = buffer[4..<(4 + Int(length))]
///             messages.append(Message(messageData))
///             buffer = buffer.dropFirst(4 + Int(length))
///         }
///         
///         return (messages, buffer)
///     }
/// }
/// ```
///
/// ## Stacking Framers
///
/// Multiple Framers can be stacked. According to RFC 9622 §9.1.2.1:
/// - Last added runs first for outbound (LIFO)
/// - Last added runs last for inbound
///
/// ```swift
/// preconnection.addFramer(compressionFramer)  // Runs second outbound
/// preconnection.addFramer(encryptionFramer)   // Runs first outbound
/// ```
///
/// ## Topics
///
/// ### Connection Lifecycle
/// - ``connectionDidOpen(_:)``
/// - ``connectionDidClose(_:)``
///
/// ### Message Processing  
/// - ``frameOutbound(_:)``
/// - ``parseInbound(_:)``
public protocol MessageFramer: Sendable {
    
    // MARK: - Connection Lifecycle
    
    /// Called when a Connection is established, before any application data.
    ///
    /// This method allows Framers to send initial handshake data or protocol
    /// negotiation before the application sends its first Message. Common uses:
    /// - Protocol version negotiation
    /// - Authentication handshakes
    /// - Compression dictionary exchange
    ///
    /// - Parameter connection: The newly established Connection.
    /// - Returns: Data to send immediately, or empty array if none.
    /// - Throws: If initialization fails, preventing Connection use.
    ///
    /// ## Example: WebSocket Handshake
    /// ```swift
    /// func connectionDidOpen(_ connection: Connection) async throws -> [Data] {
    ///     let handshake = "GET / HTTP/1.1\r\n" +
    ///                     "Upgrade: websocket\r\n" +
    ///                     "Connection: Upgrade\r\n" +
    ///                     "Sec-WebSocket-Key: \(generateKey())\r\n" +
    ///                     "\r\n"
    ///     return [handshake.data(using: .utf8)!]
    /// }
    /// ```
    ///
    /// - Note: Data returned here is sent before any application Messages.
    func connectionDidOpen(_ connection: Connection) async throws -> [Data]
    
    /// Transforms an outbound Message into wire format data.
    ///
    /// This method is called for each Message the application sends. The Framer
    /// must encode the Message data with sufficient information for the receiver
    /// to reconstruct message boundaries.
    ///
    /// - Parameter message: The Message to be framed.
    /// - Returns: One or more Data chunks to transmit.
    /// - Throws: If the Message cannot be framed.
    ///
    /// ## Design Considerations
    ///
    /// The method returns an array to support:
    /// - Splitting large messages across multiple packets
    /// - Adding protocol headers separately from payload
    /// - Implementing message fragmentation
    ///
    /// ## Example: Line-Delimited Framing
    /// ```swift
    /// func frameOutbound(_ message: Message) async throws -> [Data] {
    ///     var frame = message.data
    ///     frame.append("\n".data(using: .utf8)!)
    ///     return [frame]
    /// }
    /// ```
    ///
    /// - Important: The framing must be parseable by ``parseInbound(_:)``
    ///   on the receiving side.
    func frameOutbound(_ message: Message) async throws -> [Data]
    
    /// Parses received bytes into complete Messages.
    ///
    /// This method is called whenever data is received from the transport. It must:
    /// 1. Parse complete Messages from the input
    /// 2. Return any incomplete data as remainder
    /// 3. Maintain parsing state across calls
    ///
    /// - Parameter bytes: New data received from the transport.
    /// - Returns: A tuple of:
    ///   - messages: Array of complete Messages parsed
    ///   - remainder: Unparsed bytes to be processed next time
    /// - Throws: If the data is malformed or violates the framing protocol.
    ///
    /// ## Stateful Parsing
    ///
    /// The remainder from one call should be prepended to bytes in the next:
    /// ```swift
    /// class StatefulFramer: MessageFramer {
    ///     private var buffer = Data()
    ///     
    ///     func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
    ///         buffer.append(bytes)
    ///         let (messages, remainder) = try parseBuffer(buffer)
    ///         buffer = remainder
    ///         return (messages, Data())  // Keep remainder internal
    ///     }
    /// }
    /// ```
    ///
    /// ## Error Handling
    ///
    /// Throw errors for:
    /// - Invalid framing headers
    /// - Corrupted message boundaries  
    /// - Protocol violations
    ///
    /// These errors will typically close the Connection.
    func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data)
    
    /// Called when the Connection is closing or has closed.
    ///
    /// This optional method allows cleanup of Framer resources. It's called:
    /// - After the last Message is sent/received
    /// - When the Connection is aborted
    /// - On any Connection termination
    ///
    /// - Parameter connection: The Connection that is closing.
    ///
    /// ## Cleanup Example
    /// ```swift  
    /// func connectionDidClose(_ connection: Connection) {
    ///     // Release compression dictionaries
    ///     compressionContext = nil
    ///     // Log for diagnostics
    ///     logger.debug("Framer closed for connection \(connection.id)")
    /// }
    /// ```
    ///
    /// - Note: This is called for notification only. Errors thrown here
    ///   are ignored since the Connection is already closing.
    func connectionDidClose(_ connection: Connection)
}

// MARK: - Default Implementation

extension MessageFramer {
    /// Default implementation returns empty data array.
    public func connectionDidOpen(_ connection: Connection) async throws -> [Data] {
        return []
    }
    
    /// Default implementation does nothing.
    public func connectionDidClose(_ connection: Connection) {
        // No-op
    }
}