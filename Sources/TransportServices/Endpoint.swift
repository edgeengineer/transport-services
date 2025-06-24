#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A fully-qualified description of a network endpoint.
///
/// An Endpoint represents a transport address as defined in RFC 9622 §6.1.
/// It combines an endpoint identifier (hostname or IP address) with optional
/// qualifiers like port, service name, and network interface.
///
/// ## Overview
///
/// Endpoints are fundamental to establishing connections in Transport Services.
/// They identify:
/// - **Where to connect** (for Remote Endpoints)
/// - **Where to listen** (for Local Endpoints)
/// - **Network constraints** (via interface specification)
///
/// ## Endpoint Identifiers
///
/// According to RFC 9622, each Endpoint must have exactly one identifier:
/// - **Hostname**: DNS name to be resolved (e.g., "example.com")
/// - **IP Address**: Specific IPv4 or IPv6 address
///
/// The API design prohibits multiple identifiers of the same type per Endpoint.
/// To specify multiple addresses, use multiple Endpoint objects.
///
/// ## Usage Examples
///
/// ### Remote Endpoint with Hostname
/// ```swift
/// var remote = RemoteEndpoint(kind: .host("api.example.com"))
/// remote.service = "https"  // Will use port 443
/// ```
///
/// ### Local Endpoint with Interface
/// ```swift
/// var local = LocalEndpoint(kind: .host("0.0.0.0"))
/// local.port = 8080
/// local.interface = "en0"  // Bind to specific interface
/// ```
///
/// ### IPv6 Endpoint with Scope
/// ```swift
/// var endpoint = Endpoint(kind: .ip("fe80::1"))
/// endpoint.interface = "en0"  // Required for link-local addresses
/// ```
///
/// ## Port and Service Resolution
///
/// Ports can be specified either:
/// - Explicitly via ``port``
/// - Implicitly via ``service`` name (e.g., "https" → 443)
///
/// If both are specified, ``port`` takes precedence.
///
/// ## Interface Constraints
///
/// The ``interface`` property serves different purposes:
/// - **On Remote Endpoints**: Qualifies scope zones for link-local addresses
/// - **On Local Endpoints**: Explicitly binds to that interface
///
/// ## Name Resolution
///
/// For hostnames, the Transport Services System performs DNS resolution
/// internally when establishing connections. Applications should:
/// - Provide Fully Qualified Domain Names (FQDNs) when possible
/// - Use ``Preconnection/resolve()`` for early resolution when needed
///
/// ## Topics
///
/// ### Creating Endpoints
/// - ``init(kind:)``
/// - ``Kind``
///
/// ### Endpoint Properties
/// - ``kind``
/// - ``port``
/// - ``service``
/// - ``interface``
///
/// ### Type Aliases
/// - ``LocalEndpoint``
/// - ``RemoteEndpoint``
public struct Endpoint: Sendable, Hashable {
    
    // MARK: - Types
    
    /// The identifier type for an Endpoint.
    ///
    /// Each Endpoint must have exactly one identifier, as specified in RFC 9622 §6.1.
    /// Multiple identifiers require multiple Endpoint objects.
    public enum Kind: Sendable, Hashable {
        /// A hostname to be resolved via DNS.
        ///
        /// Applications should provide Fully Qualified Domain Names (FQDNs)
        /// to avoid relying on DNS search domains, which can lead to
        /// inconsistent behavior.
        ///
        /// - Parameter hostname: The DNS name (e.g., "example.com")
        case host(String)
        
        /// A specific IP address (IPv4 or IPv6).
        ///
        /// When using IPv6 link-local addresses (fe80::/10), you must also
        /// specify an interface to qualify the scope zone.
        ///
        /// - Parameter address: The IP address as a string
        ///
        /// ## Examples
        /// - IPv4: "192.0.2.1"
        /// - IPv6: "2001:db8::1"
        /// - IPv6 link-local: "fe80::1" (requires interface)
        case ip(_ address: String)
    }
    
    // MARK: - Properties
    
    /// The endpoint identifier (hostname or IP address).
    ///
    /// This is the primary identifier for the Endpoint and determines
    /// how the Transport Services System will resolve and connect to it.
    public var kind: Kind
    
    /// The transport port number.
    ///
    /// Specifies the port for connection or listening. Common values:
    /// - 80: HTTP
    /// - 443: HTTPS
    /// - 22: SSH
    ///
    /// If nil and no ``service`` is specified:
    /// - For Local Endpoints: System assigns ephemeral port
    /// - For Remote Endpoints: Protocol-specific default is used
    public var port: UInt16?
    
    /// The service name for port resolution.
    ///
    /// Alternative to specifying a numeric port. The system resolves
    /// standard service names to port numbers (e.g., "https" → 443).
    ///
    /// If both ``port`` and ``service`` are specified, ``port`` takes
    /// precedence. This follows the POSIX getaddrinfo() convention.
    ///
    /// Common service names:
    /// - "http": Port 80
    /// - "https": Port 443
    /// - "ssh": Port 22
    /// - "ftp": Port 21
    public var service: String?
    
    /// The network interface constraint.
    ///
    /// The meaning depends on the Endpoint type:
    ///
    /// **For Local Endpoints:**
    /// - Explicitly binds to this interface for listening or connecting
    /// - Example: "en0", "lo0"
    ///
    /// **For Remote Endpoints:**
    /// - Qualifies the scope zone for IPv6 link-local addresses
    /// - Required when using fe80::/10 addresses
    /// - Example: "fe80::1%en0"
    ///
    /// - Note: Interface names are platform-specific and can change.
    ///   Use with caution in persistent configurations.
    public var interface: String?
    
    // MARK: - Initialization
    
    /// Creates an Endpoint with the specified identifier.
    ///
    /// - Parameter kind: The endpoint identifier (hostname or IP address).
    ///
    /// ## Example
    /// ```swift
    /// // Hostname endpoint
    /// let remote = Endpoint(kind: .host("example.com"))
    /// 
    /// // IP address endpoint
    /// let local = Endpoint(kind: .ip("127.0.0.1"))
    /// ```
    public init(kind: Kind) {
        self.kind = kind
    }
}

// MARK: - Type Aliases

/// An Endpoint representing a local network address.
///
/// Local Endpoints are used to specify where to bind for:
/// - Listening for incoming connections (servers)
/// - Originating outgoing connections (source address)
///
/// ## Requirements
/// - **Listen**: At least one Local Endpoint MUST be specified
/// - **Initiate**: Local Endpoints are optional (ephemeral if not specified)
/// - **Rendezvous**: At least one Local Endpoint MUST be specified
///
/// ## Example
/// ```swift
/// var local = LocalEndpoint(kind: .host("0.0.0.0"))
/// local.port = 8080
/// local.interface = "en0"
/// ```
public typealias LocalEndpoint = Endpoint

/// An Endpoint representing a remote network address.
///
/// Remote Endpoints identify the destination for:
/// - Outgoing connections (clients)
/// - Filtering incoming connections (servers)
///
/// ## Requirements
/// - **Initiate**: At least one Remote Endpoint MUST be specified
/// - **Listen**: Remote Endpoints are optional (for filtering)
/// - **Rendezvous**: At least one Remote Endpoint MUST be specified
///
/// ## Example
/// ```swift
/// var remote = RemoteEndpoint(kind: .host("api.example.com"))
/// remote.port = 443
/// ```
public typealias RemoteEndpoint = Endpoint

// MARK: - CustomStringConvertible

extension Endpoint: CustomStringConvertible {
    public var description: String {
        var components: [String] = []
        
        switch kind {
        case .host(let hostname):
            components.append(hostname)
        case .ip(let address):
            // Wrap IPv6 addresses in brackets if port is specified
            if address.contains(":") && port != nil {
                components.append("[\(address)]")
            } else {
                components.append(address)
            }
        }
        
        if let port = port {
            components.append(":\(port)")
        } else if let service = service {
            components.append("(\(service))")
        }
        
        if let interface = interface {
            components.append("%\(interface)")
        }
        
        return components.joined()
    }
}

// MARK: - Convenience Initializers

extension Endpoint {
    /// Creates an Endpoint for the loopback interface.
    ///
    /// - Parameters:
    ///   - port: The port number to use.
    ///   - ipv6: Whether to use IPv6 (::1) or IPv4 (127.0.0.1).
    /// - Returns: A loopback Endpoint.
    public static func loopback(port: UInt16? = nil, ipv6: Bool = false) -> Endpoint {
        var endpoint = Endpoint(kind: .ip(ipv6 ? "::1" : "127.0.0.1"))
        endpoint.port = port
        return endpoint
    }
    
    /// Creates an Endpoint that binds to all available interfaces.
    ///
    /// - Parameters:
    ///   - port: The port number to bind to.
    ///   - ipv6: Whether to use IPv6 (::) or IPv4 (0.0.0.0).
    /// - Returns: An all-interfaces Endpoint.
    public static func any(port: UInt16? = nil, ipv6: Bool = false) -> Endpoint {
        var endpoint = Endpoint(kind: .ip(ipv6 ? "::" : "0.0.0.0"))
        endpoint.port = port
        return endpoint
    }
}