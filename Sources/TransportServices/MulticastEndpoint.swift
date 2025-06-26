#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Multicast-specific endpoint configurations.
///
/// This extends the Endpoint type with multicast-specific configurations
/// as specified in RFC 9622 §6.1.1 and §6.1.5.
public struct MulticastEndpoint: Sendable {
    
    // MARK: - Types
    
    /// Type of multicast group
    public enum MulticastType: Sendable {
        /// Any-Source Multicast (ASM) - receivers accept from any sender
        case anySource
        
        /// Source-Specific Multicast (SSM) - receivers only from specific sources
        case sourceSpecific(sources: [String])
    }
    
    // MARK: - Properties
    
    /// The multicast group address (IPv4 or IPv6)
    public let groupAddress: String
    
    /// The multicast type
    public let type: MulticastType
    
    /// The port number for the multicast group
    public let port: UInt16
    
    /// The network interface to use (optional)
    public let interface: String?
    
    /// Time-to-live for multicast packets
    public let ttl: UInt8
    
    /// Whether to enable multicast loopback
    public let loopback: Bool
    
    // MARK: - Initialization
    
    /// Creates a multicast endpoint for Any-Source Multicast (ASM)
    public init(groupAddress: String,
                port: UInt16,
                interface: String? = nil,
                ttl: UInt8 = 1,
                loopback: Bool = false) {
        self.groupAddress = groupAddress
        self.type = .anySource
        self.port = port
        self.interface = interface
        self.ttl = ttl
        self.loopback = loopback
    }
    
    /// Creates a multicast endpoint for Source-Specific Multicast (SSM)
    public init(groupAddress: String,
                sources: [String],
                port: UInt16,
                interface: String? = nil,
                ttl: UInt8 = 1,
                loopback: Bool = false) {
        self.groupAddress = groupAddress
        self.type = .sourceSpecific(sources: sources)
        self.port = port
        self.interface = interface
        self.ttl = ttl
        self.loopback = loopback
    }
    
    // MARK: - Conversion
    
    /// Converts to a LocalEndpoint for listening
    public func toLocalEndpoint() -> LocalEndpoint {
        var endpoint = LocalEndpoint(kind: .ip(groupAddress))
        endpoint.port = port
        endpoint.interface = interface
        return endpoint
    }
    
    /// Converts to a RemoteEndpoint for sending
    public func toRemoteEndpoint() -> RemoteEndpoint {
        var endpoint = RemoteEndpoint(kind: .ip(groupAddress))
        endpoint.port = port
        return endpoint
    }
}

// MARK: - Endpoint Extensions

extension Endpoint {
    /// Creates an endpoint configured for multicast
    public static func multicast(_ multicast: MulticastEndpoint) -> Endpoint {
        var endpoint = Endpoint(kind: .ip(multicast.groupAddress))
        endpoint.port = multicast.port
        endpoint.interface = multicast.interface
        return endpoint
    }
    
    /// Checks if this endpoint represents a multicast address
    public var isMulticast: Bool {
        switch kind {
        case .ip(let address):
            return isMulticastAddress(address)
        case .host:
            return false
        case .bluetoothPeripheral(_, _), .bluetoothService(_, _):
            return false
        }
    }
    
    private func isMulticastAddress(_ address: String) -> Bool {
        // IPv4 multicast: 224.0.0.0 - 239.255.255.255
        if address.contains(".") {
            let parts = address.split(separator: ".").compactMap { Int($0) }
            if parts.count == 4, let first = parts.first {
                return first >= 224 && first <= 239
            }
        }
        
        // IPv6 multicast: ff00::/8
        if address.contains(":") {
            return address.lowercased().hasPrefix("ff")
        }
        
        return false
    }
}

// MARK: - Transport Properties Extensions

extension TransportProperties {
    /// Direction for multicast connections
    public enum MulticastDirection: Sendable {
        /// Send-only multicast (for sources)
        case sendOnly
        
        /// Receive-only multicast (for receivers)
        case receiveOnly
        
        /// Both send and receive (for ASM rendezvous)
        case bidirectional
    }
    
    /// Multicast-specific transport properties
    public struct MulticastProperties: Sendable {
        /// The direction of the multicast connection
        public var direction: MulticastDirection = .receiveOnly
        
        /// Whether to join the multicast group
        public var joinGroup: Bool = true
        
        /// Interface index for multicast operations
        public var interfaceIndex: Int32?
        
        /// Source filtering for SSM
        public var sourceFilter: [String]?
        
        public init() {}
    }
}