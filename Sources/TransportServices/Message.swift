#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The atomic unit of data transfer in the Transport Services API.
///
/// A Message represents a discrete unit of data to be transmitted over a
/// Connection, as defined in RFC 9622 §9. Messages provide a higher-level
/// abstraction than raw bytes, allowing applications to work with logical
/// data units that the transport layer can optimize for transmission.
///
/// ## Overview
///
/// Messages are the fundamental data transfer unit in Transport Services,
/// replacing the traditional stream-oriented or datagram-oriented APIs with
/// a unified message-based interface. Each Message consists of:
/// - The actual data to be transmitted
/// - Optional metadata controlling how it's transmitted (MessageContext)
///
/// ## Message Boundaries
///
/// Messages preserve logical boundaries between data units. For protocols that
/// naturally support message boundaries (like UDP or SCTP), these are preserved
/// end-to-end. For byte-stream protocols (like TCP), Message Framers can be
/// used to reconstruct boundaries at the receiver.
///
/// ## Atomic Transmission
///
/// According to RFC 9622, Messages support "asynchronous, atomic transmission."
/// This means:
/// - Each Send action enqueues a complete Message atomically
/// - The Message is transmitted as a logical unit
/// - Partial Messages can be sent using the endOfMessage parameter
/// - Exactly one Send event (Sent, Expired, or SendError) per Send call
///
/// ## Usage Examples
///
/// ### Basic Message Send
/// ```swift
/// // Simple message with default properties
/// let message = Message("Hello, World!".data(using: .utf8)!)
/// try await connection.send(message)
/// ```
///
/// ### Message with Context
/// ```swift
/// // Time-sensitive message with custom properties
/// let context = MessageContext.timeSensitive(lifetime: .seconds(5))
/// let message = Message(jsonData, context: context)
/// try await connection.send(message)
/// ```
///
/// ### Final Message
/// ```swift
/// // Send last message and close connection for sending
/// let finalMessage = Message(
///     "Goodbye".data(using: .utf8)!,
///     context: .finalMessage()
/// )
/// try await connection.send(finalMessage)
/// ```
///
/// ## Size Constraints
///
/// Message size is constrained by:
/// - The Connection's `sendMsgMaxLen` property
/// - Protocol-specific limits (e.g., UDP datagram size)
/// - Network MTU when fragmentation is disabled
///
/// Attempting to send a Message larger than these limits results in a SendError.
///
/// ## Partial Messages
///
/// For streaming large data, Messages can be sent in parts:
/// ```swift
/// // First part
/// let context = MessageContext()
/// connection.send(firstChunk, context: context, endOfMessage: false)
///
/// // Last part
/// connection.send(lastChunk, context: context, endOfMessage: true)
/// ```
///
/// All parts with the same MessageContext are treated as a single logical Message.
///
/// ## Protocol Examples
///
/// The interpretation of a Message depends on the underlying protocol:
/// - **UDP**: Each Message becomes a single datagram
/// - **TCP**: Messages are concatenated; boundaries need Framers
/// - **SCTP**: Each Message becomes an SCTP message with preserved boundaries
/// - **HTTP**: Each Message could represent an HTTP request or response
///
/// ## Topics
///
/// ### Creating Messages
/// - ``init(_:context:)``
///
/// ### Message Components
/// - ``data``
/// - ``context``
///
/// ### Convenience Initializers
/// - ``init(string:encoding:context:)``
public struct Message: Sendable {
    
    // MARK: - Properties
    
    /// The data to be transmitted.
    ///
    /// This contains the actual bytes to be sent over the Connection.
    /// The data is treated as an opaque byte sequence by the transport layer.
    ///
    /// - Note: For protocols without native message boundaries (like TCP),
    ///   consider using Message Framers to preserve boundaries at the receiver.
    public var data: Data
    
    /// Metadata and properties controlling transmission behavior.
    ///
    /// The MessageContext allows per-Message customization of properties like:
    /// - Priority and scheduling
    /// - Reliability and ordering
    /// - Expiration time
    /// - Fragmentation behavior
    ///
    /// If not specified, the Message inherits the Connection's default properties.
    public var context: MessageContext
    
    // MARK: - Initialization
    
    /// Creates a new Message with data and optional context.
    ///
    /// - Parameters:
    ///   - data: The data to be transmitted.
    ///   - context: Optional metadata for transmission control.
    ///     If not provided, uses default MessageContext.
    ///
    /// - Note: According to RFC 9622 §9.2.1, sending without a MessageContext
    ///   is equivalent to using a default context without custom properties.
    public init(_ data: Data, context: MessageContext = .init()) {
        self.data = data
        self.context = context
    }
}

// MARK: - Convenience Initializers

extension Message {
    /// Creates a Message from a String.
    ///
    /// - Parameters:
    ///   - string: The string to encode and send.
    ///   - encoding: The string encoding to use (default: UTF-8).
    ///   - context: Optional metadata for transmission control.
    /// - Returns: A Message if the string could be encoded, nil otherwise.
    public init?(string: String, 
                 encoding: String.Encoding = .utf8,
                 context: MessageContext = .init()) {
        guard let data = string.data(using: encoding) else {
            return nil
        }
        self.init(data, context: context)
    }
}

// MARK: - CustomDebugStringConvertible

extension Message: CustomDebugStringConvertible {
    public var debugDescription: String {
        let dataDesc = data.count <= 64 
            ? data.debugDescription 
            : "<\(data.count) bytes>"
        return "Message(\(dataDesc), context: \(context.debugDescription))"
    }
}