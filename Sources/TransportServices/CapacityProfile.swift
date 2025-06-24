#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Network treatment preferences for traffic optimization.
///
/// CapacityProfile specifies the desired network treatment for traffic sent
/// by the application, as defined in RFC 9622 §8.1.6. It allows applications
/// to express their performance requirements and trade-offs, enabling the
/// Transport Services System to optimize path selection, protocol configuration,
/// and network markings.
///
/// ## Overview
///
/// Different applications have different network requirements:
/// - Interactive apps need low latency
/// - Streaming apps need consistent bandwidth
/// - Bulk transfers need maximum throughput
/// - Background tasks should not interfere with other traffic
///
/// The capacity profile communicates these needs to the transport layer.
///
/// ## Network Quality of Service
///
/// When supported, capacity profiles map to Differentiated Services Code Points
/// (DSCPs) for network-level QoS. The specific DSCP mappings follow RFC 2597,
/// RFC 3246, and related standards.
///
/// ## Usage Examples
///
/// ### Connection-Level Profile
/// ```swift
/// let properties = TransportProperties()
/// properties.connCapacityProfile = .lowLatencyInteractive
/// let connection = try await preconnection.initiate()
/// ```
///
/// ### Per-Message Override
/// ```swift
/// var context = MessageContext()
/// context.capacityProfile = .scavenger  // Override for this message
/// let message = Message(bulkData, context: context)
/// ```
///
/// ## Topics
///
/// ### Traffic Classes
/// - ``default``
/// - ``scavenger``
/// - ``lowLatencyInteractive``
/// - ``lowLatencyNonInteractive``
/// - ``constantRate``
/// - ``capacitySeeking``
public enum CapacityProfile: Sendable {
    
    /// Default best-effort delivery.
    ///
    /// The application provides no information about its capacity requirements.
    /// This is the standard treatment for most Internet traffic.
    ///
    /// **Characteristics:**
    /// - No special treatment
    /// - Fair sharing of available capacity
    /// - Standard congestion control
    ///
    /// **DSCP Mapping:** Default Forwarding (DSCP 0)
    ///
    /// **Use Cases:**
    /// - General web browsing
    /// - Email
    /// - File downloads without urgency
    case `default`
    
    /// Background traffic with minimal impact on other flows.
    ///
    /// The application is not interactive and can tolerate significant delays.
    /// This traffic yields to all other traffic classes.
    ///
    /// **Characteristics:**
    /// - Lowest priority
    /// - Uses only spare capacity
    /// - May be delayed indefinitely
    /// - Scavenger congestion control
    ///
    /// **DSCP Mapping:** Lower Effort (LE, DSCP 1) per RFC 8622
    ///
    /// **Use Cases:**
    /// - Software updates
    /// - Cloud backups
    /// - Pre-fetching content
    /// - Peer-to-peer file sharing
    ///
    /// ## Implementation Notes
    /// According to RFC 9622, this may select protocols with scavenger
    /// congestion control (e.g., LEDBAT) that detect and yield to other traffic.
    case scavenger
    
    /// Interactive traffic requiring minimal latency.
    ///
    /// The application is interactive and prefers packet loss over delay.
    /// Response time is optimized at the expense of:
    /// - Delay variation (jitter)
    /// - Efficient capacity usage
    ///
    /// **Characteristics:**
    /// - Highest priority for latency
    /// - May disable Nagle algorithm
    /// - Prefers immediate acknowledgments
    /// - No coalescing of small messages
    ///
    /// **DSCP Mapping:** Assured Forwarding 4x (AF41-44)
    /// - Expedited Forwarding (EF) for inelastic flows
    ///
    /// **Use Cases:**
    /// - Real-time gaming
    /// - Video conferencing
    /// - Remote desktop
    /// - Trading applications
    ///
    /// ## Latency Optimizations
    /// This profile may trigger:
    /// - Disabling Nagle's algorithm
    /// - Enabling TCP_NODELAY
    /// - Preferring QUIC over TCP
    /// - Selecting low-latency paths in multipath
    case lowLatencyInteractive
    
    /// Latency-sensitive traffic without user interaction.
    ///
    /// The application prefers low latency but doesn't have interactive
    /// user input. Similar optimizations to interactive but may allow
    /// some batching.
    ///
    /// **Characteristics:**
    /// - Low latency preferred
    /// - Some message coalescing allowed
    /// - Loss preferred over delay
    ///
    /// **DSCP Mapping:** Assured Forwarding 2x (AF21-24)
    ///
    /// **Use Cases:**
    /// - Live streaming (broadcast)
    /// - IoT sensor data
    /// - Monitoring metrics
    /// - Push notifications
    case lowLatencyNonInteractive
    
    /// Constant bitrate streaming traffic.
    ///
    /// The application sends/receives data at a consistent rate and needs
    /// minimal jitter. The Connection may fail if the network cannot sustain
    /// the required rate.
    ///
    /// **Characteristics:**
    /// - Consistent bandwidth required
    /// - Minimal delay variation (jitter)
    /// - Prefers circuit breaker over adaptation
    /// - May negotiate bandwidth reservation
    ///
    /// **DSCP Mapping:** Assured Forwarding 3x (AF31-34)
    ///
    /// **Use Cases:**
    /// - VoIP calls
    /// - Live video streaming
    /// - Broadcast media
    /// - Industrial control systems
    ///
    /// ## Rate Control
    /// According to RFC 9622, this profile:
    /// - Prefers circuit breakers (RFC 8084) over rate-adaptive control
    /// - May fail if constant rate cannot be maintained
    /// - Suitable for inelastic flows
    case constantRate
    
    /// Bulk transfer seeking maximum throughput.
    ///
    /// The application wants to transfer data as fast as possible using
    /// all available capacity. This is for long-lived, throughput-oriented
    /// transfers.
    ///
    /// **Characteristics:**
    /// - Maximize throughput
    /// - Aggressive congestion control
    /// - Large send/receive buffers
    /// - May use multiple paths
    ///
    /// **DSCP Mapping:** Assured Forwarding 1x (AF11-14)
    ///
    /// **Use Cases:**
    /// - Large file transfers
    /// - Database replication
    /// - Scientific data sets
    /// - Content distribution
    ///
    /// ## Throughput Optimizations
    /// This profile may:
    /// - Enable TCP Fast Open
    /// - Use larger congestion windows
    /// - Prefer BBR or CUBIC congestion control
    /// - Aggregate multiple paths in multipath
    case capacitySeeking
}

// MARK: - Profile Characteristics

extension CapacityProfile {
    /// Whether this profile prioritizes low latency.
    public var prefersLowLatency: Bool {
        switch self {
        case .lowLatencyInteractive, .lowLatencyNonInteractive:
            return true
        default:
            return false
        }
    }
    
    /// Whether this profile is suitable for interactive applications.
    public var isInteractive: Bool {
        self == .lowLatencyInteractive
    }
    
    /// Whether this profile requires consistent bandwidth.
    public var requiresConsistentRate: Bool {
        self == .constantRate
    }
    
    /// Whether this profile yields to other traffic.
    public var isBackground: Bool {
        self == .scavenger
    }
    
    /// Relative priority level (0 = highest, 5 = lowest).
    public var priorityLevel: Int {
        switch self {
        case .lowLatencyInteractive: return 0
        case .lowLatencyNonInteractive: return 1
        case .constantRate: return 2
        case .default: return 3
        case .capacitySeeking: return 4
        case .scavenger: return 5
        }
    }
}

// MARK: - CustomStringConvertible

extension CapacityProfile: CustomStringConvertible {
    public var description: String {
        switch self {
        case .default: return "Default"
        case .scavenger: return "Scavenger"
        case .lowLatencyInteractive: return "Low Latency/Interactive"
        case .lowLatencyNonInteractive: return "Low Latency/Non-Interactive"
        case .constantRate: return "Constant-Rate Streaming"
        case .capacitySeeking: return "Capacity-Seeking"
        }
    }
}