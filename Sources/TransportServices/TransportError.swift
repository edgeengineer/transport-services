#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Errors that can occur during Transport Services operations.
///
/// TransportError represents the various failure conditions defined throughout
/// RFC 9622, providing structured error information for Connection establishment,
/// data transfer, and termination scenarios.
///
/// ## Error Categories
///
/// Transport errors fall into several categories based on when they occur:
/// - **Establishment**: Failures during Connection setup
/// - **Data Transfer**: Failures during send/receive operations  
/// - **Termination**: Connection closure conditions
///
/// ## Error Handling Pattern
///
/// ```swift
/// do {
///     let connection = try await preconnection.initiate()
///     try await connection.send(message)
/// } catch let error as TransportError {
///     switch error {
///     case .establishmentFailure(let reason):
///         print("Failed to connect: \(reason ?? "Unknown")")
///     case .sendFailure(let reason):
///         print("Failed to send: \(reason ?? "Unknown")")
///     default:
///         print("Transport error: \(error)")
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Establishment Errors
/// - ``establishmentFailure(_:)``
///
/// ### Data Transfer Errors
/// - ``sendFailure(_:)``
/// - ``receiveFailure(_:)``
///
/// ### Connection State Errors
/// - ``connectionClosed``
/// - ``cancelled``
public enum TransportError: Error, Sendable {
    
    // MARK: - Establishment Errors
    
    /// Connection establishment failed.
    ///
    /// According to RFC 9622 §7, EstablishmentError occurs when:
    /// - Transport properties cannot be satisfied
    /// - No usable network paths exist
    /// - Remote endpoint cannot be resolved
    /// - Remote endpoint refuses connection
    /// - Security requirements cannot be met
    /// - Establishment timeout exceeded
    ///
    /// - Parameter reason: Optional human-readable failure description.
    ///
    /// ## Common Causes
    ///
    /// **Network Issues:**
    /// ```swift
    /// case .establishmentFailure("Network unreachable")
    /// case .establishmentFailure("No route to host") 
    /// ```
    ///
    /// **Endpoint Issues:**
    /// ```swift
    /// case .establishmentFailure("DNS resolution failed")
    /// case .establishmentFailure("Connection refused")
    /// ```
    ///
    /// **Protocol Issues:**
    /// ```swift
    /// case .establishmentFailure("No compatible protocols")
    /// case .establishmentFailure("TLS handshake failed")
    /// ```
    ///
    /// - Note: After this error, the Connection transitions directly to
    ///   the Closed state without ever becoming Established.
    case establishmentFailure(String?)
    
    // MARK: - Data Transfer Errors
    
    /// Message transmission failed.
    ///
    /// According to RFC 9622 §9.2.2.3, SendError occurs when:
    /// - Message is too large for the protocol
    /// - Message properties are incompatible with Connection
    /// - Connection is in wrong state for sending
    /// - Protocol stack failure during transmission
    /// - Resources exhausted (buffers, memory)
    ///
    /// - Parameter reason: Optional failure description.
    ///
    /// ## Size Constraint Example
    /// ```swift
    /// // UDP datagram too large
    /// case .sendFailure("Message exceeds maximum datagram size (65507 bytes)")
    /// 
    /// // Fragmentation prohibited but required
    /// case .sendFailure("Message too large for path MTU with fragmentation disabled")
    /// ```
    ///
    /// ## Property Conflict Example
    /// ```swift
    /// // Reliability mismatch
    /// case .sendFailure("Cannot send unreliable message on reliable-only connection")
    /// 
    /// // Ordering conflict  
    /// case .sendFailure("Cannot send unordered message on order-preserving connection")
    /// ```
    ///
    /// - Important: This error doesn't close the Connection. The application
    ///   can continue sending other Messages.
    case sendFailure(String?)
    
    /// Message reception failed.
    ///
    /// According to RFC 9622 §9.3, receive failures can occur due to:
    /// - Corrupted data that cannot be parsed
    /// - Framer protocol violations
    /// - Checksum failures (for partial coverage)
    /// - Resource exhaustion during receive
    ///
    /// - Parameter reason: Optional failure description.
    ///
    /// ## Framing Errors
    /// ```swift
    /// case .receiveFailure("Invalid message framing")
    /// case .receiveFailure("Message boundary corrupted")
    /// ```
    ///
    /// ## Data Integrity Errors
    /// ```swift
    /// case .receiveFailure("Checksum verification failed")
    /// case .receiveFailure("Decompression failed")
    /// ```
    ///
    /// - Note: Depending on the severity, receive failures may or may not
    ///   close the Connection.
    case receiveFailure(String?)
    
    // MARK: - Connection State Errors
    
    /// Connection has been closed.
    ///
    /// This error indicates operations were attempted on a Connection that
    /// has already transitioned to the Closed state. According to RFC 9622 §11,
    /// no operations are valid after closure.
    ///
    /// Common scenarios:
    /// - Sending after calling `close()`
    /// - Sending after receiving a final Message
    /// - Operations after connection timeout
    /// - Operations after abort
    ///
    /// ## Prevention
    /// ```swift
    /// // Check state before operations
    /// guard await connection.state == .established else {
    ///     throw TransportError.connectionClosed  
    /// }
    /// ```
    ///
    /// - Note: This is distinct from a ConnectionError event, which
    ///   indicates the Connection failed while active.
    case connectionClosed
    
    /// Operation was cancelled.
    ///
    /// Indicates that an asynchronous operation was cancelled before completion.
    /// This typically occurs when:
    /// - The containing task is cancelled
    /// - A timeout is reached
    /// - The application explicitly cancels an operation
    ///
    /// ## Cancellation Handling
    /// ```swift
    /// let task = Task {
    ///     do {
    ///         try await connection.send(largeMessage)
    ///     } catch TransportError.cancelled {
    ///         print("Send was cancelled")
    ///     }
    /// }
    /// 
    /// // Later...
    /// task.cancel()  // Triggers cancelled error
    /// ```
    ///
    /// - Note: Cancellation is considered a normal flow control mechanism,
    ///   not a fatal error.
    case cancelled
    
    /// Operation or feature is not supported.
    ///
    /// Indicates that the requested operation or feature is not implemented
    /// or not available on the current platform. This typically occurs for:
    /// - Platform-specific features not available on all systems
    /// - Features that are planned but not yet implemented
    /// - Protocol-specific operations on incompatible connections
    ///
    /// - Parameter reason: Description of what is not supported.
    ///
    /// ## Examples
    /// ```swift
    /// case .notSupported("Multicast interface selection requires platform-specific APIs")
    /// case .notSupported("SCTP protocol not available on this platform")
    /// case .notSupported("Hardware offload not supported by network interface")
    /// ```
    case notSupported(String)
}

// MARK: - Error Descriptions

extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .establishmentFailure(let reason):
            return reason ?? "Connection establishment failed"
        case .sendFailure(let reason):
            return reason ?? "Failed to send message"
        case .receiveFailure(let reason):
            return reason ?? "Failed to receive message"
        case .connectionClosed:
            return "Connection is closed"
        case .cancelled:
            return "Operation was cancelled"
        case .notSupported(let reason):
            return reason
        }
    }
}

// MARK: - Error Classification

extension TransportError {
    /// Whether this error occurs during connection establishment.
    public var isEstablishmentError: Bool {
        if case .establishmentFailure = self {
            return true
        }
        return false
    }
    
    /// Whether this error occurs during data transfer.
    public var isDataTransferError: Bool {
        switch self {
        case .sendFailure, .receiveFailure:
            return true
        case .establishmentFailure, .connectionClosed, .cancelled, .notSupported:
            return false
        }
    }
    
    /// Whether this error indicates the Connection cannot be used.
    public var isTerminal: Bool {
        switch self {
        case .establishmentFailure, .connectionClosed:
            return true
        case .sendFailure, .receiveFailure, .cancelled, .notSupported:
            return false
        }
    }
}