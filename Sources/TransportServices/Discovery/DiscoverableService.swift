#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A service configuration for discovery and advertising
///
/// This struct represents a service that can be discovered or advertised
/// across different transport mechanisms (IP via mDNS/Bonjour, Bluetooth, etc.)
public struct DiscoverableService: Sendable {
    /// The transport type for discovery
    public enum Transport: Sendable {
        /// IP-based discovery (mDNS/Bonjour)
        case ip
        /// Bluetooth Low Energy discovery
        case bluetooth
        /// Any available transport
        case any
    }
    
    /// The service type identifier
    ///
    /// For mDNS: Use standard service types like "_http._tcp"
    /// For Bluetooth: Use a UUID string representing the service UUID
    public let type: String
    
    /// The discovery domain (optional)
    ///
    /// For mDNS: Typically "local." for local network discovery
    /// For Bluetooth: Not used, can be nil
    public let domain: String?
    
    /// Key-value metadata to broadcast
    ///
    /// For mDNS: Maps to TXT records
    /// For Bluetooth: Maps to advertising data/service data
    public let metadata: [String: String]
    
    /// The preferred transport for discovery
    public let transport: Transport
    
    /// Creates a new discoverable service configuration
    ///
    /// - Parameters:
    ///   - type: The service type identifier
    ///   - domain: The discovery domain (optional)
    ///   - metadata: Key-value metadata to broadcast
    ///   - transport: The preferred transport (defaults to .any)
    public init(
        type: String,
        domain: String? = nil,
        metadata: [String: String] = [:],
        transport: Transport = .any
    ) {
        self.type = type
        self.domain = domain
        self.metadata = metadata
        self.transport = transport
    }
}

// MARK: - Convenience Initializers

extension DiscoverableService {
    /// Creates a discoverable service for mDNS/Bonjour
    ///
    /// - Parameters:
    ///   - serviceType: The mDNS service type (e.g., "_http._tcp")
    ///   - domain: The domain (defaults to "local.")
    ///   - metadata: TXT record data
    public static func mdns(
        serviceType: String,
        domain: String = "local.",
        metadata: [String: String] = [:]
    ) -> DiscoverableService {
        DiscoverableService(
            type: serviceType,
            domain: domain,
            metadata: metadata,
            transport: .ip
        )
    }
    
    /// Creates a discoverable service for Bluetooth
    ///
    /// - Parameters:
    ///   - serviceUUID: The Bluetooth service UUID
    ///   - metadata: Service data to include in advertising
    public static func ble(
        serviceUUID: UUID,
        metadata: [String: String] = [:]
    ) -> DiscoverableService {
        DiscoverableService(
            type: serviceUUID.uuidString,
            domain: nil,
            metadata: metadata,
            transport: .bluetooth
        )
    }
}