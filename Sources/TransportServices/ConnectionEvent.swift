#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Unified strongly-typed events for Connection lifecycle and data transfer.
///
/// ConnectionEvent provides a type-safe enumeration of all events that can
/// occur on a Connection, as defined throughout RFC 9622. This allows
/// applications to handle Connection events through a single stream interface
/// rather than multiple callbacks.
///
/// ## Overview
///
/// Connection events fall into several categories:
/// - **Lifecycle**: Connection establishment, closure, and errors
/// - **Data Transfer**: Message reception
/// - **Network Changes**: Path changes and soft errors
///
/// ## Event Stream Pattern
///
/// ```swift
/// for await event in connection.events {
///     switch event {
///     case .ready:
///         print("Connection established")
///     case .received(let message):
///         await processMessage(message)
///     case .pathChange:
///         print("Network path changed")
///     case .softError(let error):
///         print("Soft error: \(error)")
///     case .closed:
///         print("Connection closed gracefully")
///     case .connectionError(let error):
///         print("Connection failed: \(error)")
///         break  // Terminal event
///     }
/// }
/// ```
///
/// ## Event Ordering
///
/// RFC 9622 §11 guarantees:
/// - No events after ``closed`` or ``connectionError``
/// - No ``received`` events before ``ready``
/// - Events are delivered in order of occurrence
///
/// ## Topics
///
/// ### Lifecycle Events
/// - ``ready``
/// - ``closed``
/// - ``connectionError(_:)``
///
/// ### Data Transfer Events
/// - ``received(_:)``
///
/// ### Network Events
/// - ``pathChange``
/// - ``softError(_:)``
public enum ConnectionEvent: Sendable {
    
    // MARK: - Lifecycle Events
    
    /// Connection has been established and is ready for use.
    ///
    /// According to RFC 9622 §7.1, the Ready event occurs after a transport-layer
    /// connection is established on at least one usable candidate path. For
    /// client connections (initiated), no Receive events will occur before Ready.
    ///
    /// After this event:
    /// - The Connection state is ``ConnectionState/established``
    /// - Messages can be sent and received
    /// - Connection properties can be queried
    ///
    /// ## Client Example
    /// ```swift
    /// let connection = try await preconnection.initiate()
    /// // Ready event is emitted when connection is established
    /// ```
    ///
    /// - Note: For server connections, use ConnectionReceived on the Listener
    ///   instead, as those Connections are already Ready when delivered.
    case ready
    
    /// A complete Message has been received.
    ///
    /// According to RFC 9622 §9.3.2.1, a Received event indicates delivery of
    /// a complete Message. The Message boundaries are preserved either by the
    /// transport protocol or by Message Framers.
    ///
    /// - Parameter message: The received Message with its data and context.
    ///
    /// ## Handling Received Messages
    /// ```swift
    /// case .received(let message):
    ///     let data = message.data
    ///     let context = message.context
    ///     
    ///     // Check message properties
    ///     if context.final {
    ///         print("Peer has closed for sending")
    ///     }
    /// ```
    ///
    /// - Note: For partial message reception, protocols may deliver
    ///   ReceivedPartial events (not modeled in this simplified API).
    case received(Message)
    
    /// Network path characteristics have changed.
    ///
    /// According to RFC 9622 §8.3.2, this event notifies when at least one
    /// path underlying the Connection has changed. Changes include:
    /// - Path MTU changes
    /// - Addition or removal of paths (multipath)
    /// - Local endpoint changes
    /// - Network handovers
    ///
    /// ## Response to Path Changes
    /// ```swift
    /// case .pathChange:
    ///     // Re-query connection properties
    ///     let currentMTU = await connection.pathMTU
    ///     let endpoints = await connection.localEndpoints
    /// ```
    ///
    /// - Note: Path changes may affect Connection performance characteristics
    ///   like RTT, available bandwidth, or reliability.
    case pathChange
    
    /// ICMP or similar error received (non-fatal).
    ///
    /// According to RFC 9622 §8.3.1, soft errors inform the application about
    /// ICMP error messages related to the Connection. These are advisory and
    /// don't terminate the Connection.
    ///
    /// Common soft errors:
    /// - ICMP Destination Unreachable (temporary)
    /// - ICMP Packet Too Big (triggers path MTU discovery)
    /// - ICMP Time Exceeded
    ///
    /// - Parameter error: The soft error information.
    ///
    /// ## Soft Error Handling
    /// ```swift
    /// case .softError(let error):
    ///     // Log for diagnostics but continue operation
    ///     logger.warning("Soft error: \(error)")
    ///     // Connection remains usable
    /// ```
    ///
    /// - Important: Even if the underlying stack supports soft errors,
    ///   there's no guarantee they will be signaled.
    case softError(Error)
    
    /// Connection closed gracefully.
    ///
    /// According to RFC 9622 §10, the Closed event occurs when the Connection
    /// transitions to the Closed state without error. This is the result of:
    /// - Local application calling `close()`
    /// - Peer initiating graceful shutdown
    /// - Successful completion of closing handshake
    ///
    /// After this event:
    /// - No further events will be delivered
    /// - The Connection cannot send or receive data
    /// - Resources have been released
    ///
    /// - Note: This is a terminal event. The Connection object should be
    ///   discarded after receiving this event.
    case closed
    
    /// Connection terminated due to error.
    ///
    /// According to RFC 9622 §10, ConnectionError informs that:
    /// 1. Data could not be delivered after timeout
    /// 2. The Connection was aborted
    /// 3. A fatal protocol error occurred
    ///
    /// - Parameter error: The error that caused termination.
    ///
    /// Common causes:
    /// - Network unreachable
    /// - Connection timeout (connTimeout exceeded)
    /// - Protocol violations
    /// - Resource exhaustion
    /// - Remote abort
    ///
    /// ## Error Handling
    /// ```swift
    /// case .connectionError(let error):
    ///     if let transportError = error as? TransportError {
    ///         switch transportError {
    ///         case .establishmentFailure:
    ///             // Handle based on context
    ///         default:
    ///             // Handle other errors
    ///         }
    ///     }
    /// ```
    ///
    /// - Note: This is a terminal event. No further events will follow.
    case connectionError(Error)
}

// MARK: - Event Classification

extension ConnectionEvent {
    /// Whether this event indicates the Connection is no longer usable.
    ///
    /// Returns `true` for ``closed`` and ``connectionError(_:)``.
    public var isTerminal: Bool {
        switch self {
        case .closed, .connectionError:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event carries data.
    ///
    /// Returns `true` only for ``received(_:)``.
    public var hasData: Bool {
        if case .received = self {
            return true
        }
        return false
    }
    
    /// Whether this event indicates a network condition change.
    ///
    /// Returns `true` for ``pathChange`` and ``softError(_:)``.
    public var isNetworkEvent: Bool {
        switch self {
        case .pathChange, .softError:
            return true
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension ConnectionEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ready:
            return "Ready"
        case .received(let message):
            return "Received(\(message.data.count) bytes)"
        case .pathChange:
            return "PathChange"
        case .softError(let error):
            return "SoftError(\(error))" 
        case .closed:
            return "Closed"
        case .connectionError(let error):
            return "ConnectionError(\(error))"
        }
    }
}