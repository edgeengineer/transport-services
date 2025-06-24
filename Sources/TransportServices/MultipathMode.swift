#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Specifies whether and how applications want to use multiple network paths.
///
/// This enumeration controls multipath transport behavior as defined in
/// RFC 9622 §6.2.14. Using multiple paths allows Connections to migrate
/// between interfaces or aggregate bandwidth as availability and performance
/// properties change.
///
/// ## Overview
///
/// Multipath transport enables connections to utilize multiple network paths
/// simultaneously or as alternatives. This can provide benefits such as:
/// - Improved reliability through path redundancy
/// - Better performance via bandwidth aggregation
/// - Seamless mobility between networks
/// - Reduced latency through path selection
///
/// ## Default Behavior
///
/// According to RFC 9622:
/// - **Initiate/Rendezvous**: Defaults to ``disabled``
/// - **Listen**: Defaults to ``passive``
///
/// ## Privacy Considerations
///
/// Setting multipath to ``active`` can have privacy implications:
/// - Users may be linkable across multiple paths
/// - This occurs even if `advertisesAltaddr` is false
/// - Consider privacy requirements when enabling multipath
///
/// ## Relationship to Protocol Selection
///
/// Unlike other properties, multipath doesn't use the Preference type:
/// - ``active`` and ``passive`` indicate preference for multipath protocols
/// - ``disabled`` prevents multipath usage but allows multipath-capable protocols
/// - For example, TCP can be selected with ``disabled``, but MP_CAPABLE won't be sent
///
/// ## Topics
///
/// ### Multipath Modes
/// - ``disabled``
/// - ``passive``
/// - ``active``
///
/// ### Related Properties
/// - Use `multipathPolicy` (RFC 9622 §8.1.7) to control path usage policy
/// - Use `advertisesAltaddr` (RFC 9622 §6.2.15) to control address advertisement
public enum MultipathMode: String, Sendable, CaseIterable {
    /// The Connection will not use multiple paths once established.
    ///
    /// Even if the chosen transport supports multiple paths (e.g., MPTCP),
    /// the connection will be restricted to a single path. This prevents
    /// features like:
    /// - Path migration on network changes
    /// - Bandwidth aggregation across interfaces
    /// - Redundant transmission for reliability
    ///
    /// This is the default for connections created through Initiate and Rendezvous.
    ///
    /// - Note: This doesn't prevent selection of multipath-capable protocols,
    ///   but disables their multipath features (e.g., MP_CAPABLE in MPTCP).
    case disabled
    
    /// The Connection will support multiple paths if the Remote Endpoint requests it.
    ///
    /// The local endpoint will not proactively establish additional paths,
    /// but will respond to multipath requests from the peer. This mode:
    /// - Allows the peer to initiate additional subflows
    /// - Supports path migration initiated by the peer
    /// - Requires less local resources than active mode
    ///
    /// This is the default for Listeners, allowing servers to support
    /// multipath clients without forcing multipath on all connections.
    ///
    /// ## Server Example
    /// ```swift
    /// let properties = TransportProperties()
    /// properties.multipathMode = .passive  // Default for listeners
    /// let listener = try await preconnection.listen()
    /// ```
    case passive
    
    /// The Connection will negotiate the use of multiple paths if supported.
    ///
    /// The local endpoint will proactively attempt to:
    /// - Establish multiple subflows across available interfaces
    /// - Discover and use alternative paths
    /// - Migrate between paths based on availability and performance
    ///
    /// The actual behavior depends on:
    /// - Transport protocol support (e.g., MPTCP, QUIC multipath)
    /// - Available network interfaces
    /// - The configured `multipathPolicy`
    ///
    /// ## Privacy Warning
    /// Active multipath can link user identity across paths. Consider:
    /// - Users may be trackable across different networks
    /// - This occurs even without advertising alternate addresses
    /// - Evaluate privacy requirements before enabling
    ///
    /// ## Client Example
    /// ```swift
    /// let properties = TransportProperties()
    /// properties.multipathMode = .active
    /// properties.multipathPolicy = .aggregate  // Use all paths
    /// ```
    case active
}

// MARK: - Convenience Properties

extension MultipathMode {
    /// Returns whether this mode allows multipath usage.
    ///
    /// - Returns: `true` for ``active`` and ``passive``, `false` for ``disabled``.
    public var allowsMultipath: Bool {
        self != .disabled
    }
    
    /// Returns whether this mode proactively initiates multiple paths.
    ///
    /// - Returns: `true` only for ``active`` mode.
    public var isProactive: Bool {
        self == .active
    }
    
    /// Returns the default mode based on connection type.
    ///
    /// - Parameter isListener: Whether this is for a listening connection.
    /// - Returns: ``passive`` for listeners, ``disabled`` for initiating connections.
    public static func defaultMode(isListener: Bool) -> MultipathMode {
        isListener ? .passive : .disabled
    }
}

// MARK: - CustomStringConvertible

extension MultipathMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disabled: return "Disabled"
        case .passive: return "Passive"
        case .active: return "Active"
        }
    }
}

// MARK: - Related Types

/// Policy for using multiple paths when multipath is enabled.
///
/// This enumeration is defined in RFC 9622 §8.1.7 and controls how
/// multiple paths are utilized when `multipathMode` is not ``disabled``.
///
/// - Note: This is a separate property from MultipathMode and only
///   applies when multipath is enabled.
public enum MultipathPolicy: String, Sendable, CaseIterable {
    /// Migrate between paths only when the current path fails.
    ///
    /// The connection uses a single path at a time, switching only when:
    /// - The current path is lost
    /// - The path becomes unusable (implementation-defined thresholds)
    ///
    /// This provides reliability without the overhead of multiple active paths.
    case handover
    
    /// Minimize latency by using multiple paths intelligently.
    ///
    /// The connection may:
    /// - Send data on multiple paths in parallel
    /// - Choose paths based on latency characteristics
    /// - Balance latency benefits against path costs
    ///
    /// The specific scheduling algorithm is implementation-specific.
    case interactive
    
    /// Maximize throughput by aggregating multiple paths.
    ///
    /// The connection attempts to:
    /// - Use all available paths in parallel
    /// - Overcome individual path capacity limits
    /// - Maximize total available bandwidth
    ///
    /// The actual strategy is implementation-specific.
    case aggregate
}