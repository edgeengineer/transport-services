#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The lifecycle state of a Connection.
///
/// ConnectionState represents the current phase of a Connection's lifecycle
/// as defined in RFC 9622 §11. Connections transition through these states
/// in response to establishment actions, data transfer, and termination.
///
/// ## State Transitions
///
/// According to RFC 9622, Connections follow this state diagram:
///
/// ```
///               (*)                               (**)
/// Establishing -----> Established -----> Closing ------> Closed
///      |                                                   ^
///      |                                                   |
///      +---------------------------------------------------+
///                   EstablishmentError
///
/// (*) Ready, ConnectionReceived, RendezvousDone
/// (**) Closed, ConnectionError
/// ```
///
/// ## State Descriptions
///
/// Each state represents a specific phase in the Connection lifecycle:
/// - ``establishing``: Connection setup in progress
/// - ``established``: Ready for data transfer
/// - ``closing``: Graceful shutdown initiated
/// - ``closed``: Connection terminated
///
/// ## Associated Events
///
/// State transitions trigger specific events:
/// - **Establishing → Established**: Ready (client), ConnectionReceived (server), or RendezvousDone (peer)
/// - **Establishing → Closed**: EstablishmentError
/// - **Established → Closing**: Application calls close()
/// - **Closing → Closed**: Closed (graceful) or ConnectionError
/// - **Any → Closed**: ConnectionError (on abort)
///
/// ## Guarantees
///
/// RFC 9622 §11 provides these ordering guarantees:
/// 1. No Receive events before Established state
/// 2. No events after Closed state
/// 3. Send events occur in order
/// 4. Closed event waits for outstanding events
///
/// ## Usage Example
///
/// ```swift
/// // Monitor connection state
/// switch await connection.state {
/// case .establishing:
///     print("Connection setup in progress...")
/// case .established:
///     print("Ready for data transfer")
/// case .closing:
///     print("Shutting down gracefully")
/// case .closed:
///     print("Connection terminated")
/// }
/// ```
///
/// ## Topics
///
/// ### Connection States
/// - ``establishing``
/// - ``established``
/// - ``closing``
/// - ``closed``
public enum ConnectionState: Sendable {
    /// Connection establishment is in progress.
    ///
    /// The Connection is performing protocol negotiation, name resolution,
    /// and path selection. No data can be sent or received in this state.
    ///
    /// **Transitions to:**
    /// - ``established``: On successful establishment
    /// - ``closed``: On establishment failure (with EstablishmentError)
    ///
    /// **Entry via:**
    /// - `Preconnection.initiate()`
    /// - `Preconnection.listen()` (for each new connection)
    /// - `Preconnection.rendezvous()`
    ///
    /// ## Protocol-Specific Behavior
    ///
    /// The duration and operations in this state depend on the protocol:
    /// - **TCP**: Three-way handshake
    /// - **TLS/TCP**: TCP handshake + TLS negotiation
    /// - **QUIC**: Combined transport and security handshake
    /// - **UDP**: Immediate transition (connectionless)
    case establishing
    
    /// Connection is active and ready for data transfer.
    ///
    /// The Connection has successfully completed establishment and can
    /// send and receive Messages. This is the primary operational state.
    ///
    /// **Capabilities in this state:**
    /// - Send Messages (unless send-closed)
    /// - Receive Messages (unless receive-closed)
    /// - Query Connection properties
    /// - Clone the Connection
    ///
    /// **Transitions to:**
    /// - ``closing``: When `close()` is called
    /// - ``closed``: On fatal error (with ConnectionError)
    ///
    /// **Entry via:**
    /// - Successful completion of ``establishing`` state
    ///
    /// ## Available Operations
    ///
    /// While Established, applications can:
    /// - `send()`: Transmit Messages
    /// - `receive()`: Receive Messages
    /// - Query properties like RTT, path MTU
    /// - Manage Connection priority
    case established
    
    /// Connection is shutting down gracefully.
    ///
    /// The Connection has initiated termination but may still be
    /// transmitting queued data or waiting for acknowledgments.
    ///
    /// **Behavior in this state:**
    /// - No new Messages accepted for sending
    /// - Previously queued Messages may still be transmitted
    /// - May still receive Messages from the peer
    /// - Waiting for graceful shutdown to complete
    ///
    /// **Transitions to:**
    /// - ``closed``: When shutdown completes or times out
    ///
    /// **Entry via:**
    /// - Application calls `close()` on ``established`` Connection
    /// - Receiving a final Message from peer
    ///
    /// ## Protocol Examples
    ///
    /// - **TCP**: FIN-WAIT states, TIME-WAIT
    /// - **QUIC**: Draining period after CONNECTION_CLOSE
    /// - **SCTP**: SHUTDOWN sequence
    case closing
    
    /// Connection has terminated.
    ///
    /// The Connection is no longer usable and all resources have been
    /// released. No further events will be delivered.
    ///
    /// **Guarantees in this state:**
    /// - No new events will be delivered
    /// - All outstanding events have been processed
    /// - Resources have been released
    /// - Connection object can be safely discarded
    ///
    /// **Entry via:**
    /// - Graceful close from ``closing`` state
    /// - EstablishmentError from ``establishing`` state
    /// - ConnectionError from any state
    /// - Abort operation
    ///
    /// ## Final Events
    ///
    /// The transition to Closed generates one of:
    /// - **Closed**: Normal termination
    /// - **EstablishmentError**: Failed during establishment
    /// - **ConnectionError**: Failed after establishment
    case closed
}

// MARK: - Convenience Properties

extension ConnectionState {
    /// Whether the Connection is operational for data transfer.
    ///
    /// Returns `true` only in the ``established`` state.
    public var isOperational: Bool {
        self == .established
    }
    
    /// Whether the Connection is in a terminal state.
    ///
    /// Returns `true` for ``closed`` state, indicating no further
    /// state transitions are possible.
    public var isTerminal: Bool {
        self == .closed
    }
    
    /// Whether the Connection is in a transitional state.
    ///
    /// Returns `true` for ``establishing`` and ``closing`` states,
    /// which are temporary states leading to others.
    public var isTransitional: Bool {
        self == .establishing || self == .closing
    }
}

// MARK: - CustomStringConvertible

extension ConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .establishing: return "Establishing"
        case .established: return "Established"
        case .closing: return "Closing"
        case .closed: return "Closed"
        }
    }
}