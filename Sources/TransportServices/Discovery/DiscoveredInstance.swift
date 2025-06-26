#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A discovered service instance
///
/// This struct represents a single discovered service instance,
/// containing all the information needed to connect to it.
public struct DiscoveredInstance: Sendable {
    /// The human-readable name of the instance
    ///
    /// For mDNS: The instance name (e.g., "Alice's MacBook Pro")
    /// For BLE: The peripheral's local name
    public let name: String
    
    /// A list of resolved endpoints for connecting
    ///
    /// This array may contain multiple endpoints if the service
    /// is available via multiple transports (e.g., both IP and BLE)
    public let endpoints: [Endpoint]
    
    /// The metadata broadcast by the service
    ///
    /// For mDNS: TXT record data
    /// For BLE: Service data from advertising packet
    public let metadata: [String: String]
    
    /// The transport type(s) this instance was discovered via
    public enum TransportType: String, Sendable {
        case ip = "IP"
        case bluetooth = "Bluetooth"
    }
    
    /// The transport type(s) available for this instance
    public let availableTransports: Set<TransportType>
    
    /// Creates a new discovered instance
    ///
    /// - Parameters:
    ///   - name: The human-readable name
    ///   - endpoints: The available endpoints for connection
    ///   - metadata: Service metadata
    ///   - availableTransports: The transport types available
    public init(
        name: String,
        endpoints: [Endpoint],
        metadata: [String: String] = [:],
        availableTransports: Set<TransportType> = []
    ) {
        self.name = name
        self.endpoints = endpoints
        self.metadata = metadata
        
        // If availableTransports is empty, infer from endpoints
        if availableTransports.isEmpty {
            var transports = Set<TransportType>()
            for endpoint in endpoints {
                switch endpoint.kind {
                case .host, .ip:
                    transports.insert(.ip)
                case .bluetoothPeripheral, .bluetoothService:
                    transports.insert(.bluetooth)
                }
            }
            self.availableTransports = transports
        } else {
            self.availableTransports = availableTransports
        }
    }
}

// MARK: - Convenience Properties

extension DiscoveredInstance {
    /// Returns true if this instance is available via IP
    public var hasIPEndpoint: Bool {
        availableTransports.contains(.ip)
    }
    
    /// Returns true if this instance is available via Bluetooth
    public var hasBluetoothEndpoint: Bool {
        availableTransports.contains(.bluetooth)
    }
    
    /// Returns true if this instance is available via multiple transports
    public var isMultiTransport: Bool {
        availableTransports.count > 1
    }
}