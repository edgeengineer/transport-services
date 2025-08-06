//
//  WindowsPreconnection.swift
//  
//
//  Maximilian Alexander
//

#if os(Windows)
import WinSDK
import Foundation

/// Windows platform-specific preconnection implementation
public final class WindowsPreconnection: Preconnection, @unchecked Sendable {
    public var localEndpoints: [LocalEndpoint]
    public var remoteEndpoints: [RemoteEndpoint]
    public var transportProperties: TransportProperties
    public var securityParameters: SecurityParameters?
    
    public init(
        localEndpoints: [LocalEndpoint] = [],
        remoteEndpoints: [RemoteEndpoint] = [],
        transportProperties: TransportProperties = TransportProperties(),
        securityParameters: SecurityParameters? = nil
    ) {
        self.localEndpoints = localEndpoints
        self.remoteEndpoints = remoteEndpoints
        self.transportProperties = transportProperties
        self.securityParameters = securityParameters
        
        // Initialize Winsock if not already done
        WindowsCompat.initializeWinsock()
    }
    
    // MARK: - Preconnection Protocol Implementation
    
    public func establish(eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Connection {
        let connection = WindowsConnection(
            preconnection: self,
            eventHandler: eventHandler
        )
        
        // Start connection establishment asynchronously
        Task {
            await connection.initiate()
        }
        
        return connection
    }
    
    public func listen(eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Listener {
        let listener = WindowsListener(
            preconnection: self,
            eventHandler: eventHandler
        )
        
        // Start listening asynchronously
        Task {
            do {
                try await listener.listen()
            } catch {
                eventHandler(.listenerError(listener, reason: error.localizedDescription))
            }
        }
        
        return listener
    }
    
    // MARK: - Endpoint Management
    
    public func addLocalEndpoint(_ endpoint: LocalEndpoint) {
        if !localEndpoints.contains(where: { $0.ipAddress == endpoint.ipAddress && $0.port == endpoint.port }) {
            localEndpoints.append(endpoint)
        }
    }
    
    public func removeLocalEndpoint(_ endpoint: LocalEndpoint) {
        localEndpoints.removeAll { $0.ipAddress == endpoint.ipAddress && $0.port == endpoint.port }
    }
    
    public func addRemoteEndpoint(_ endpoint: RemoteEndpoint) {
        if !remoteEndpoints.contains(where: { 
            $0.hostName == endpoint.hostName && 
            $0.ipAddress == endpoint.ipAddress && 
            $0.port == endpoint.port 
        }) {
            remoteEndpoints.append(endpoint)
        }
    }
    
    public func removeRemoteEndpoint(_ endpoint: RemoteEndpoint) {
        remoteEndpoints.removeAll { 
            $0.hostName == endpoint.hostName && 
            $0.ipAddress == endpoint.ipAddress && 
            $0.port == endpoint.port 
        }
    }
    
    // MARK: - Configuration Methods
    
    public func setTransportProperty(_ property: String, value: Any) {
        // This would be extended to support more properties
        switch property {
        case "reliability":
            if let reliability = value as? Preference {
                transportProperties.reliability = reliability
            }
        case "ordering":
            if let ordering = value as? Preference {
                transportProperties.ordering = ordering
            }
        case "congestionControl":
            if let congestionControl = value as? Preference {
                transportProperties.congestionControl = congestionControl
            }
        case "keepAlive":
            if let keepAlive = value as? Preference {
                transportProperties.keepAlive = keepAlive
            }
        case "multipath":
            if let multipath = value as? Multipath {
                transportProperties.multipath = multipath
            }
        default:
            break
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create a clone of this preconnection with the same configuration
    internal func clone() -> WindowsPreconnection {
        return WindowsPreconnection(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            transportProperties: transportProperties,
            securityParameters: securityParameters
        )
    }
    
    /// Validate that the preconnection has minimum required configuration
    internal func validate() throws {
        // For connections, we need at least a remote endpoint
        if remoteEndpoints.isEmpty {
            // For listeners, we need at least a local endpoint
            if localEndpoints.isEmpty {
                throw WindowsPreconnectionError.noEndpointsSpecified
            }
        }
        
        // Validate endpoints have required information
        for remote in remoteEndpoints {
            if remote.hostName == nil && remote.ipAddress == nil {
                throw WindowsPreconnectionError.invalidRemoteEndpoint
            }
            if remote.port == nil {
                throw WindowsPreconnectionError.missingPort
            }
        }
        
        for local in localEndpoints {
            // Local endpoints can have nil port (will be assigned by system)
            // But if specified, validate the IP address
            if local.ipAddress != nil && !isValidIPAddress(local.ipAddress!) {
                throw WindowsPreconnectionError.invalidLocalEndpoint
            }
        }
    }
    
    /// Check if a string is a valid IP address
    private func isValidIPAddress(_ address: String) -> Bool {
        // Try to parse as IPv4
        var addr4 = in_addr()
        if inet_pton(WindowsCompat.AF_INET, address, &addr4) == 1 {
            return true
        }
        
        // Try to parse as IPv6
        var addr6 = in6_addr()
        if inet_pton(WindowsCompat.AF_INET6, address, &addr6) == 1 {
            return true
        }
        
        return false
    }
    
    // MARK: - Static Factory Methods
    
    /// Create a preconnection for a client connection
    public static func client(
        to remoteEndpoint: RemoteEndpoint,
        from localEndpoint: LocalEndpoint? = nil,
        properties: TransportProperties = TransportProperties()
    ) -> WindowsPreconnection {
        var localEndpoints: [LocalEndpoint] = []
        if let localEndpoint = localEndpoint {
            localEndpoints.append(localEndpoint)
        }
        
        return WindowsPreconnection(
            localEndpoints: localEndpoints,
            remoteEndpoints: [remoteEndpoint],
            transportProperties: properties
        )
    }
    
    /// Create a preconnection for a server listener
    public static func server(
        on localEndpoint: LocalEndpoint,
        properties: TransportProperties = TransportProperties()
    ) -> WindowsPreconnection {
        return WindowsPreconnection(
            localEndpoints: [localEndpoint],
            remoteEndpoints: [],
            transportProperties: properties
        )
    }
}

/// Windows-specific preconnection errors
enum WindowsPreconnectionError: Error, LocalizedError {
    case noEndpointsSpecified
    case invalidRemoteEndpoint
    case invalidLocalEndpoint
    case missingPort
    
    var errorDescription: String? {
        switch self {
        case .noEndpointsSpecified:
            return "No endpoints specified for connection or listener"
        case .invalidRemoteEndpoint:
            return "Remote endpoint must have either hostname or IP address"
        case .invalidLocalEndpoint:
            return "Invalid local endpoint IP address"
        case .missingPort:
            return "Remote endpoint must specify a port number"
        }
    }
}

#endif