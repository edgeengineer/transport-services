#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Metadata and properties associated with a Message for sending or receiving.
///
/// MessageContext allows applications to annotate Messages with properties
/// that control transport behavior, as defined in RFC 9622 §9.1.1. It provides
/// a way to set per-Message properties that can override Connection-level
/// defaults and influence how data is scheduled, processed, and transmitted.
///
/// ## Overview
///
/// Each Message has an optional MessageContext that can:
/// - Control reliability, ordering, and priority
/// - Set transmission deadlines and capacity profiles
/// - Configure checksums and fragmentation behavior
/// - Identify Messages for tracking Send/Receive events
///
/// ## Usage
///
/// ```swift
/// let context = MessageContext()
/// context.priority = 50              // Higher priority than default
/// context.lifetime = .seconds(30)    // Expire if not sent within 30s
/// context.reliable = false           // Override connection reliability
/// 
/// let message = Message(data, context: context)
/// try await connection.send(message)
/// ```
///
/// ## Property Precedence
///
/// Message Properties follow this precedence order:
/// 1. Properties explicitly set on the MessageContext
/// 2. Connection-level defaults
/// 3. System/protocol defaults
///
/// ## Topics
///
/// ### Identification
/// - ``id``
///
/// ### Timing and Expiration
/// - ``lifetime``
///
/// ### Scheduling and Priority
/// - ``priority``
/// - ``capacityProfile``
///
/// ### Ordering and Reliability
/// - ``ordered``
/// - ``reliable``
/// - ``safelyReplayable``
///
/// ### Connection Management
/// - ``final``
///
/// ### Data Integrity
/// - ``checksumCoverage``
/// - ``Checksum``
///
/// ### Fragmentation Control
/// - ``noFragmentation``
/// - ``noSegmentation``
public struct MessageContext: Sendable, Hashable {
    
    // MARK: - Identification
    
    /// Unique identifier for this Message.
    ///
    /// This UUID allows applications to correlate Send events (Sent, Expired,
    /// SendError) with specific Messages. The system generates this automatically
    /// but applications can set their own identifiers if needed.
    public var id: UUID = .init()
    
    // MARK: - Timing Properties
    
    /// Maximum time before the Message expires if not sent.
    ///
    /// Specifies how long a Message can wait in the Transport Services System
    /// before transmission. After this duration, the Message becomes irrelevant
    /// and no longer needs to be transmitted. An Expired event will be generated.
    ///
    /// This is defined in RFC 9622 §9.1.3.1 as a hint to the system—there's no
    /// guarantee that a Message won't be sent after expiration.
    ///
    /// - Note: Setting to `nil` indicates infinite lifetime (default).
    ///
    /// ## Example
    /// ```swift
    /// context.lifetime = .seconds(5)  // Expire after 5 seconds
    /// ```
    public var lifetime: Duration? = nil
    
    // MARK: - Scheduling Properties
    
    /// Priority relative to other Messages on the same Connection.
    ///
    /// Lower numeric values indicate higher priority. Messages with priority 0
    /// will be sent before priority 1, which will be sent before priority 2, etc.
    /// This affects sender-side scheduling and may influence on-wire priority
    /// for protocols that support it.
    ///
    /// Defined in RFC 9622 §9.1.3.2. Default is 100.
    ///
    /// ## Priority Ordering
    /// - Priority 0: Highest priority
    /// - Priority 1-99: Higher than default
    /// - Priority 100: Default priority
    /// - Priority 101+: Lower than default
    ///
    /// - Note: Connection priority takes precedence over Message priority
    ///   when scheduling across multiple Connections in a group.
    public var priority: Int = 100
    
    /// Capacity profile for this specific Message.
    ///
    /// Overrides the Connection's capacity profile for this Message only.
    /// This allows fine-grained control over latency/throughput trade-offs
    /// on a per-Message basis.
    ///
    /// Defined in RFC 9622 §9.1.3.8. If `nil`, inherits from Connection.
    public var capacityProfile: CapacityProfile? = nil
    
    // MARK: - Ordering and Reliability
    
    /// Whether to preserve ordering relative to other ordered Messages.
    ///
    /// When `true`, this Message will be delivered in the order it was sent
    /// relative to other ordered Messages. When `false`, the Message may be
    /// delivered out of order, potentially reducing latency.
    ///
    /// Defined in RFC 9622 §9.1.3.3. If `nil`, inherits from the Connection's
    /// preserveOrder property.
    ///
    /// - Note: The underlying protocol must support message ordering.
    public var ordered: Bool? = nil
    
    /// Whether this Message requires reliable delivery.
    ///
    /// Controls per-Message reliability for protocols that support it.
    /// When `true`, the Message will be retransmitted if lost. When `false`,
    /// the Message may be dropped without retransmission.
    ///
    /// Defined in RFC 9622 §9.1.3.7. If `nil`, inherits from the Connection's
    /// reliability property.
    ///
    /// - Note: Requires perMsgReliability to be enabled on the Connection.
    public var reliable: Bool? = nil
    
    /// Whether this Message is safe to transmit multiple times.
    ///
    /// Marks the Message as idempotent, making it safe for 0-RTT establishment
    /// techniques where data might be replayed. Only set this for Messages that
    /// won't cause problems if received multiple times (e.g., GET requests).
    ///
    /// Defined in RFC 9622 §9.1.3.4. Default is `false`.
    ///
    /// ## Security Warning
    /// Only mark Messages as safely replayable if processing them multiple
    /// times has no adverse effects. Never use for:
    /// - State-changing operations
    /// - Financial transactions
    /// - One-time tokens
    public var safelyReplayable: Bool = false
    
    // MARK: - Connection Lifecycle
    
    /// Indicates this is the last Message on the Connection.
    ///
    /// When `true`, the Connection will be closed for sending after this Message.
    /// This enables protocols to signal end-of-stream to the peer (e.g., TCP FIN).
    /// The Connection can still receive data unless the peer also sends a final Message.
    ///
    /// Defined in RFC 9622 §9.1.3.5. Default is `false`.
    ///
    /// ## Example
    /// ```swift
    /// context.final = true
    /// try await connection.send(lastMessage, context: context)
    /// // Connection is now half-closed for sending
    /// ```
    public var final: Bool = false
    
    // MARK: - Data Integrity
    
    /// Checksum coverage requirement for this Message.
    ///
    /// Specifies how much of the Message must be protected by checksums.
    /// This is primarily for protocols like UDP-Lite that support partial
    /// checksum coverage.
    ///
    /// Defined in RFC 9622 §9.1.3.6.
    public var checksumCoverage: Checksum? = nil
    
    /// Checksum coverage specification.
    ///
    /// Used with protocols that support partial checksum coverage (e.g., UDP-Lite).
    public enum Checksum: Sendable, Hashable {
        /// Cover only the first N bytes with checksum.
        ///
        /// Useful for protecting headers while allowing corruption in
        /// less critical payload data (e.g., media streams).
        case bytes(Int)
        
        /// Cover the entire Message with checksum (default).
        case full
    }
    
    // MARK: - Fragmentation Control
    
    /// Prevent network-layer fragmentation of this Message.
    ///
    /// When `true`, requests that the Message be sent without IP fragmentation.
    /// This may limit the Message size to the Path MTU. For IPv4, sets the
    /// Don't Fragment (DF) bit.
    ///
    /// Defined in RFC 9622 §9.1.3.9. Default is `false`.
    ///
    /// Use this for:
    /// - Latency-sensitive traffic that can't tolerate reassembly delays
    /// - Probing Path MTU
    /// - Avoiding fragmentation-related packet loss
    public var noFragmentation: Bool = false
    
    /// Prevent transport-layer segmentation of this Message.
    ///
    /// When `true`, requests that the transport layer not segment this Message.
    /// The entire Message should fit in a single network packet if possible.
    /// This is stronger than noFragmentation as it prevents both IP fragmentation
    /// and transport segmentation.
    ///
    /// Defined in RFC 9622 §9.1.3.10. Default is `false`.
    ///
    /// - Warning: Setting this may cause SendError if the Message exceeds
    ///   the maximum transmission unit.
    public var noSegmentation: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a new MessageContext with default values.
    ///
    /// All properties are set to their defaults as specified in RFC 9622:
    /// - lifetime: nil (infinite)
    /// - priority: 100
    /// - ordered: nil (inherit from Connection)
    /// - reliable: nil (inherit from Connection)
    /// - safelyReplayable: false
    /// - final: false
    /// - checksumCoverage: nil (full coverage)
    /// - capacityProfile: nil (inherit from Connection)
    /// - noFragmentation: false
    /// - noSegmentation: false
    public init() {}
}

// MARK: - Convenience Methods

extension MessageContext {
    /// Creates a high-priority MessageContext.
    ///
    /// - Parameter priority: The priority value (default: 0 for highest).
    /// - Returns: A MessageContext configured for high-priority transmission.
    public static func highPriority(_ priority: Int = 0) -> MessageContext {
        var context = MessageContext()
        context.priority = priority
        return context
    }
    
    /// Creates a MessageContext for time-sensitive data.
    ///
    /// - Parameters:
    ///   - lifetime: Maximum time before expiration.
    ///   - priority: Priority level (default: 50).
    /// - Returns: A MessageContext configured for time-sensitive transmission.
    public static func timeSensitive(lifetime: Duration, priority: Int = 50) -> MessageContext {
        var context = MessageContext()
        context.lifetime = lifetime
        context.priority = priority
        context.capacityProfile = .lowLatencyInteractive
        return context
    }
    
    /// Creates a MessageContext for the final Message on a Connection.
    ///
    /// - Returns: A MessageContext with the final flag set.
    public static func finalMessage() -> MessageContext {
        var context = MessageContext()
        context.final = true
        return context
    }
}

// MARK: - CustomDebugStringConvertible

extension MessageContext: CustomDebugStringConvertible {
    public var debugDescription: String {
        var parts: [String] = ["MessageContext(id: \(id)"]
        
        if let lifetime = lifetime {
            parts.append("lifetime: \(lifetime)")
        }
        if priority != 100 {
            parts.append("priority: \(priority)")
        }
        if let ordered = ordered {
            parts.append("ordered: \(ordered)")
        }
        if let reliable = reliable {
            parts.append("reliable: \(reliable)")
        }
        if safelyReplayable {
            parts.append("safelyReplayable: true")
        }
        if final {
            parts.append("final: true")
        }
        if let profile = capacityProfile {
            parts.append("capacityProfile: \(profile)")
        }
        if noFragmentation {
            parts.append("noFragmentation: true")
        }
        if noSegmentation {
            parts.append("noSegmentation: true")
        }
        
        return parts.joined(separator: ", ") + ")"
    }
}