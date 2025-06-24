#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Configuration for protocol selection and Connection behavior.
///
/// TransportProperties represents the set of Selection Properties defined in
/// RFC 9622 §6.2. These properties guide the Transport Services System in
/// selecting appropriate protocols and configuring the resulting Connection.
///
/// ## Overview
///
/// Transport Properties serve two key purposes:
/// 1. **Protocol Selection**: Guide which transport protocols can satisfy the
///    application's requirements (TCP, QUIC, SCTP, etc.)
/// 2. **Connection Configuration**: Set behavioral defaults that can be
///    overridden per-Message
///
/// ## Preference System
///
/// Most properties use the ``Preference`` type with five levels:
/// - **Require**: Only select protocols providing this feature
/// - **Prefer**: Favor protocols with this feature
/// - **NoPreference**: No influence on selection
/// - **Avoid**: Favor protocols without this feature
/// - **Prohibit**: Only select protocols lacking this feature
///
/// ## Default Values
///
/// According to RFC 9622, defaults represent a TCP-compatible configuration.
/// This ensures portability across Transport Services implementations, though
/// applications should adjust properties for their specific needs.
///
/// ## Usage Examples
///
/// ### Reliable Stream (TCP-like)
/// ```swift
/// let properties = TransportProperties()
/// // Already configured by defaults:
/// // reliability = .require
/// // preserveOrder = .require
/// // congestionControl = .require
/// ```
///
/// ### Unreliable Datagram (UDP-like)
/// ```swift
/// var properties = TransportProperties()
/// properties.reliability = .prohibit
/// properties.preserveMsgBoundaries = .require
/// properties.congestionControl = .prohibit
/// ```
///
/// ### Low-Latency Interactive
/// ```swift
/// var properties = TransportProperties()
/// properties.zeroRTT = .prefer
/// properties.multipathMode = .active
/// properties.perMsgReliability = .prefer  // For selective reliability
/// ```
///
/// ## Property Conflicts
///
/// Some combinations are invalid or unlikely to succeed:
/// - Reliable but not congestion-controlled (violates RFC 2914)
/// - Temporary addresses with IPv4 (only supported in IPv6)
/// - Active multipath with privacy concerns
///
/// ## Topics
///
/// ### Data Transfer Properties
/// - ``reliability``
/// - ``preserveMsgBoundaries``
/// - ``preserveOrder``
/// - ``perMsgReliability``
///
/// ### Performance Properties
/// - ``zeroRTT``
/// - ``multistreaming``
/// - ``congestionControl``
/// - ``keepAlive``
///
/// ### Data Integrity Properties
/// - ``fullChecksumSend``
/// - ``fullChecksumRecv``
///
/// ### Path Selection Properties
/// - ``interfacePreferences``
/// - ``pvdPreferences``
/// - ``multipathMode``
/// - ``advertisesAltAddr``
///
/// ### Privacy Properties
/// - ``useTemporaryAddress``
///
/// ### Communication Properties
/// - ``direction``
/// - ``Direction``
/// - ``softErrorNotify``
/// - ``activeReadBeforeSend``
public struct TransportProperties: Sendable {
    
    // MARK: - Data Transfer Properties
    
    /// Whether the Connection must provide reliable, in-order data delivery.
    ///
    /// According to RFC 9622 §6.2.1, this property determines whether the
    /// transport ensures all data is received without loss or duplication.
    /// Reliable transports also notify when connections close or abort.
    ///
    /// **Default:** `.require` (TCP-compatible)
    ///
    /// **Protocol Examples:**
    /// - `.require`: TCP, QUIC, SCTP (reliable mode)
    /// - `.prohibit`: UDP, UDP-Lite
    ///
    /// **Implications:**
    /// - When required, data is retransmitted if lost
    /// - Connection failures are detected and signaled
    /// - Usually combined with congestion control
    public var reliability: Preference = .require
    
    /// Whether to preserve Message boundaries in the data stream.
    ///
    /// According to RFC 9622 §6.2.2, this property specifies if the transport
    /// should maintain message boundaries or can treat data as a byte stream.
    ///
    /// **Default:** `.noPreference`
    ///
    /// **Protocol Examples:**
    /// - Preserves: UDP, SCTP, QUIC (datagram mode)
    /// - Doesn't preserve: TCP (requires Message Framers)
    ///
    /// **Usage:**
    /// ```swift
    /// // For message-oriented protocols
    /// properties.preserveMsgBoundaries = .require
    /// ```
    public var preserveMsgBoundaries: Preference = .noPreference
    
    /// Whether data must be delivered in the order it was sent.
    ///
    /// According to RFC 9622 §6.2.4, this property ensures the receiving
    /// application gets data in the same sequence it was transmitted.
    ///
    /// **Default:** `.require` (TCP-compatible)
    ///
    /// **Protocol Examples:**
    /// - Ordered: TCP, SCTP (ordered mode), QUIC (stream mode)
    /// - Unordered: UDP, SCTP (unordered mode)
    ///
    /// **Performance Note:**
    /// Disabling ordering can reduce latency by avoiding head-of-line blocking.
    public var preserveOrder: Preference = .require
    
    /// Whether to allow per-Message reliability configuration.
    ///
    /// According to RFC 9622 §6.2.3, this property indicates if the application
    /// wants to specify different reliability for individual Messages.
    ///
    /// **Default:** `.noPreference`
    ///
    /// **Protocol Support:**
    /// - SCTP with PR-SCTP extension
    /// - QUIC with unreliable datagrams
    ///
    /// **Usage:**
    /// ```swift
    /// properties.perMsgReliability = .prefer
    /// // Later, per message:
    /// messageContext.reliable = false  // This message can be dropped
    /// ```
    public var perMsgReliability: Preference = .noPreference
    
    // MARK: - Performance Properties
    
    /// Whether to enable 0-RTT connection establishment.
    ///
    /// According to RFC 9622 §6.2.5, this property allows sending data during
    /// the connection handshake. The data must be safely replayable as it
    /// might be received multiple times.
    ///
    /// **Default:** `.noPreference`
    ///
    /// **Protocol Support:**
    /// - TLS 1.3 with early data
    /// - QUIC 0-RTT
    /// - TCP Fast Open
    ///
    /// **Security Warning:**
    /// Only use with idempotent data. The message must be marked with
    /// `safelyReplayable = true`.
    public var zeroRTT: Preference = .noPreference
    
    /// Whether to use streams for Connection Groups.
    ///
    /// According to RFC 9622 §6.2.6, this property indicates if multiple
    /// Connections in a group should share an underlying transport connection
    /// through multiplexing.
    ///
    /// **Default:** `.prefer`
    ///
    /// **Protocol Support:**
    /// - HTTP/2 streams
    /// - QUIC streams
    /// - SCTP multi-streaming
    ///
    /// **Benefits:**
    /// - Reduced handshake overhead
    /// - Shared congestion control
    /// - Better resource utilization
    public var multistreaming: Preference = .prefer
    
    /// Whether the Connection must be congestion controlled.
    ///
    /// According to RFC 9622 §6.2.9, this property specifies if the transport
    /// should implement congestion control per RFC 2914.
    ///
    /// **Default:** `.require`
    ///
    /// **Important:** If disabled, the application MUST either:
    /// - Implement its own congestion control
    /// - Use a circuit breaker (RFC 8084)
    ///
    /// **Note:** "Reliable but not congestion controlled" rarely succeeds.
    public var congestionControl: Preference = .require
    
    /// Whether to send keep-alive packets.
    ///
    /// According to RFC 9622 §6.2.10, this property controls whether the
    /// transport sends periodic keep-alive messages to maintain NAT bindings
    /// and detect connection failures.
    ///
    /// **Default:** `.noPreference`
    ///
    /// **Protocol Support:**
    /// - TCP keep-alive
    /// - SCTP heartbeat
    /// - Application-layer keep-alives
    ///
    /// **Note:** If enabled, applications should avoid sending their own
    /// keep-alive messages.
    public var keepAlive: Preference = .noPreference
    
    /// Whether to disable Nagle's algorithm (TCP_NODELAY).
    /// 
    /// When true, small packets are sent immediately without waiting
    /// for more data. This reduces latency but may increase overhead.
    /// 
    /// **Default:** `false`
    /// 
    /// **Use Cases:**
    /// - Interactive applications (SSH, gaming)
    /// - Real-time protocols
    /// - When sending small, time-sensitive messages
    public var disableNagle: Bool = false
    
    // MARK: - Data Integrity Properties
    
    /// Whether to require full checksum coverage when sending.
    ///
    /// According to RFC 9622 §6.2.7, this property controls corruption
    /// protection for transmitted data. Disabling allows per-Message
    /// checksum configuration.
    ///
    /// **Default:** `.require`
    ///
    /// **Protocol Examples:**
    /// - Full coverage: TCP, SCTP, QUIC
    /// - Configurable: UDP-Lite
    ///
    /// **Usage with UDP-Lite:**
    /// ```swift
    /// properties.fullChecksumSend = .avoid
    /// // Per message:
    /// messageContext.checksumCoverage = .bytes(8)  // Only header
    /// ```
    public var fullChecksumSend: Preference = .require
    
    /// Whether to require full checksum coverage when receiving.
    ///
    /// According to RFC 9622 §6.2.8, this property controls the minimum
    /// acceptable checksum coverage for received data.
    ///
    /// **Default:** `.require`
    ///
    /// **Important:** Disabling makes the application responsible for
    /// handling corruption in unprotected portions.
    public var fullChecksumRecv: Preference = .require
    
    // MARK: - Path Selection Properties
    
    /// Network interface preferences for path selection.
    ///
    /// According to RFC 9622 §6.2.11, this property controls which network
    /// interfaces to use or avoid. Interface names are platform-specific.
    ///
    /// **Default:** Empty (no preferences)
    ///
    /// **Example:**
    /// ```swift
    /// // Prefer Wi-Fi, avoid cellular
    /// properties.interfacePreferences = [
    ///     "en0": .prefer,      // Wi-Fi interface
    ///     "pdp_ip0": .avoid    // Cellular interface
    /// ]
    /// ```
    ///
    /// **Warning:** Requiring specific interfaces reduces flexibility and
    /// resilience. Use interface types via PvD preferences when possible.
    public var interfacePreferences: [String: Preference] = [:]
    
    /// Provisioning Domain preferences for path selection.
    ///
    /// According to RFC 9622 §6.2.12, Provisioning Domains (PvDs) represent
    /// consistent sets of network properties. This is more flexible than
    /// interface selection.
    ///
    /// **Default:** Empty (no preferences)
    ///
    /// **Example:**
    /// ```swift
    /// // Prefer corporate VPN, avoid public Wi-Fi
    /// properties.pvdPreferences = [
    ///     "corp.example.com": .prefer,
    ///     "public-wifi": .avoid
    /// ]
    /// ```
    public var pvdPreferences: [String: Preference] = [:]
    
    /// Whether to use temporary ("privacy") addresses.
    ///
    /// According to RFC 9622 §6.2.13, temporary addresses (RFC 8981) prevent
    /// tracking connections over time by rotating source addresses.
    ///
    /// **Default:** `.prefer` for clients, `.avoid` for servers
    ///
    /// **Limitations:**
    /// - IPv6 only (requiring temporary addresses excludes IPv4)
    /// - May interfere with connection resumption
    /// - Not suitable for servers that need stable addresses
    public var useTemporaryAddress: Preference = .prefer
    
    /// Multipath behavior for the Connection.
    ///
    /// According to RFC 9622 §6.2.14, this controls whether connections can
    /// use multiple network paths simultaneously. See ``MultipathMode`` for
    /// details.
    ///
    /// **Default:** `.disabled` for clients, `.passive` for servers
    ///
    /// **Privacy Warning:** Active multipath can link user identity across
    /// different network paths.
    public var multipathMode: MultipathMode = .disabled
    
    /// Whether to advertise alternate addresses to the peer.
    ///
    /// According to RFC 9622 §6.2.15, this controls whether local addresses
    /// on other interfaces are shared with the peer for multipath or migration.
    ///
    /// **Default:** `false`
    ///
    /// **Privacy Warning:** Advertising addresses allows tracking across paths
    /// and reveals network topology information.
    ///
    /// **Note:** This only prevents advertisement; the local system can still
    /// initiate connections on alternate paths.
    public var advertisesAltAddr: Bool = false
    
    // MARK: - Communication Properties
    
    /// Communication directionality for the Connection.
    ///
    /// According to RFC 9622 §6.2.16, this specifies whether the Connection
    /// is used for sending, receiving, or both.
    ///
    /// **Default:** `.bidirectional`
    ///
    /// **Use Cases:**
    /// - `.sendOnly`: Sensor data upload, logging
    /// - `.recvOnly`: Notification listeners, broadcasts
    /// - `.bidirectional`: Most client-server protocols
    public var direction: Direction = .bidirectional
    
    /// Whether to receive ICMP soft error notifications.
    ///
    /// According to RFC 9622 §6.2.17, this controls delivery of non-fatal
    /// ICMP errors as SoftError events.
    ///
    /// **Default:** `.noPreference`
    ///
    /// **Example Errors:**
    /// - Destination Unreachable (temporary)
    /// - Packet Too Big (triggers path MTU discovery)
    /// - Time Exceeded
    ///
    /// **Note:** Delivery is not guaranteed even if supported (RFC 8085).
    public var softErrorNotify: Preference = .noPreference
    
    /// Whether the initiator reads before writing.
    ///
    /// According to RFC 9622 §6.2.18, this property indicates non-standard
    /// communication patterns where:
    /// - Active side (client) reads first, or
    /// - Passive side (server) writes first
    ///
    /// **Default:** `.noPreference`
    ///
    /// **Limitations:**
    /// - Prevents mapping to SCTP streams
    /// - May reduce protocol selection flexibility
    /// - Not applicable to Rendezvous connections
    public var activeReadBeforeSend: Preference = .noPreference
    
    /// Multicast-specific properties
    public var multicast: MulticastProperties = MulticastProperties()
    
    // MARK: - Types
    
    /// Communication direction specification.
    ///
    /// Defines whether a Connection supports sending, receiving, or both.
    public enum Direction: Sendable {
        /// Connection supports both sending and receiving.
        ///
        /// This is the standard mode for most protocols and allows
        /// full-duplex communication.
        case bidirectional
        
        /// Connection only supports sending data.
        ///
        /// The application cannot receive any data on this Connection.
        /// Useful for:
        /// - Telemetry upload
        /// - Log streaming
        /// - Sensor data transmission
        case sendOnly
        
        /// Connection only supports receiving data.
        ///
        /// The application cannot send any data on this Connection.
        /// Useful for:
        /// - Broadcast receivers
        /// - Notification listeners
        /// - Event streams
        case recvOnly
    }
    
    // MARK: - Initialization
    
    /// Creates a TransportProperties with default values.
    ///
    /// The defaults provide a TCP-compatible configuration as specified
    /// in RFC 9622 §6.2.
    public init() {}
}

// MARK: - Convenience Methods

extension TransportProperties {
    /// Creates properties for reliable, ordered byte streams (TCP-like).
    ///
    /// This configuration is the default and suitable for:
    /// - HTTP/HTTPS
    /// - SSH
    /// - Most client-server protocols
    public static func reliableStream() -> TransportProperties {
        TransportProperties()  // Defaults are already configured
    }
    
    /// Creates properties for reliable message delivery (SCTP-like).
    ///
    /// This configuration provides reliable delivery while preserving
    /// message boundaries. Suitable for:
    /// - Protocol implementations requiring message framing
    /// - Structured data exchange
    /// - Command/response protocols
    public static func reliableMessage() -> TransportProperties {
        var properties = TransportProperties()
        properties.reliability = .require
        properties.preserveMsgBoundaries = .require
        properties.preserveOrder = .require
        properties.congestionControl = .require
        return properties
    }
    
    /// Creates properties for unreliable datagrams (UDP-like).
    ///
    /// Suitable for:
    /// - Real-time media
    /// - Gaming
    /// - IoT sensors
    public static func unreliableDatagram() -> TransportProperties {
        var properties = TransportProperties()
        properties.reliability = .prohibit
        properties.preserveMsgBoundaries = .require
        properties.congestionControl = .prohibit
        properties.preserveOrder = .avoid
        return properties
    }
    
    /// Creates properties for low-latency interactive communication.
    ///
    /// Optimized for:
    /// - Video conferencing
    /// - Online gaming
    /// - Real-time collaboration
    public static func lowLatency() -> TransportProperties {
        var properties = TransportProperties()
        properties.zeroRTT = .prefer
        properties.multipathMode = .active
        properties.perMsgReliability = .prefer
        return properties
    }
    
    /// Creates properties for bulk data transfer.
    ///
    /// Optimized for throughput over latency. Suitable for:
    /// - File transfers
    /// - Backup operations
    /// - Content distribution
    public static func bulkData() -> TransportProperties {
        var properties = TransportProperties()
        properties.reliability = .require
        properties.preserveOrder = .require
        properties.congestionControl = .require
        properties.disableNagle = false  // Allow batching
        properties.multistreaming = .prefer
        return properties
    }
    
    /// Creates properties for real-time media streaming.
    ///
    /// Optimized for continuous media delivery with:
    /// - Partial reliability (some loss tolerated)
    /// - Low latency preference
    /// - Congestion awareness
    ///
    /// Suitable for:
    /// - Live video/audio streaming
    /// - Screen sharing
    /// - Real-time sensor data
    public static func mediaStream() -> TransportProperties {
        var properties = TransportProperties()
        properties.reliability = .avoid
        properties.preserveMsgBoundaries = .prefer
        properties.preserveOrder = .prefer
        properties.perMsgReliability = .require
        properties.congestionControl = .require
        properties.zeroRTT = .prefer
        properties.disableNagle = true
        return properties
    }
    
    /// Creates properties for privacy-sensitive communication.
    ///
    /// Maximizes privacy features at potential cost of:
    /// - Connection establishment time
    /// - Path flexibility
    ///
    /// Suitable for:
    /// - Anonymous communication
    /// - Privacy-critical applications
    /// - Tor-like systems
    public static func privacyEnhanced() -> TransportProperties {
        var properties = TransportProperties()
        properties.useTemporaryAddress = .require
        properties.advertisesAltAddr = false
        properties.multipathMode = .disabled
        properties.zeroRTT = .prohibit  // Avoid replay attacks
        return properties
    }
}