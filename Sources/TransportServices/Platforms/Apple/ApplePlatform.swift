//
//  ApplePlatform.swift
//  
//
//  Maximilian Alexander
//

#if !hasFeature(Embedded)
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
#endif

// Using types from TransportServices module

#if canImport(Network)
import Network

/// Apple platform implementation using Network.framework
public struct ApplePlatform: Platform {
    
    public init() {}
    
    public func createConnection(preconnection: any Preconnection, 
                               eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Connection {
        return AppleConnection(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    
    public func gatherCandidates(preconnection: any Preconnection) async throws -> CandidateSet {
        var localCandidates: [LocalCandidate] = []
        var remoteCandidates: [RemoteCandidate] = []
        
        // Gather local candidates
        for localEndpoint in preconnection.localEndpoints {
            let addresses = try await resolveLocalEndpoint(localEndpoint)
            var interface: NetworkInterface? = nil
            if let interfaceName = localEndpoint.interface {
                interface = try? await getInterface(named: interfaceName)
            }
            localCandidates.append(LocalCandidate(
                endpoint: localEndpoint,
                addresses: addresses,
                interface: interface
            ))
        }
        
        // Gather remote candidates
        for (index, remoteEndpoint) in preconnection.remoteEndpoints.enumerated() {
            let addresses = try await resolveRemoteEndpoint(remoteEndpoint)
            remoteCandidates.append(RemoteCandidate(
                endpoint: remoteEndpoint,
                addresses: addresses,
                priority: index
            ))
        }
        
        return CandidateSet(localCandidates: localCandidates, remoteCandidates: remoteCandidates)
    }
    
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        // Check if all layers in the stack are supported
        for layer in stack.layers {
            switch layer {
            case .tcp, .udp, .tls:
                // These are supported by Network.framework
                continue
            case .quic:
                // QUIC is supported in newer versions
                if #available(iOS 15.0, macOS 12.0, *) {
                    continue
                } else {
                    return false
                }
            case .sctp, .http2, .http3, .webTransport:
                // These are not directly supported by Network.framework
                return false
            case .custom(_):
                // Custom protocols would need specific implementation
                return false
            }
        }
        return true
    }
    
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        let _: [NetworkInterface] = []
        
        // Use NWPathMonitor to get interface information
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "interface-query")
        
        return try await withCheckedThrowingContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                var foundInterfaces: [NetworkInterface] = []
                
                // Get available interfaces from the path
                for interface in path.availableInterfaces {
                    let type: NetworkInterface.InterfaceType
                    switch interface.type {
                    case .wifi:
                        type = .wifi
                    case .cellular:
                        type = .cellular
                    case .wiredEthernet:
                        type = .ethernet
                    case .loopback:
                        type = .loopback
                    default:
                        type = .other
                    }
                    
                    // Get addresses for the interface
                    let addresses = getInterfaceAddresses(interface)
                    
                    foundInterfaces.append(NetworkInterface(
                        name: interface.name,
                        index: interface.index,
                        type: type,
                        addresses: addresses,
                        isUp: true, // If it's in availableInterfaces, it's up
                        supportsMulticast: interface.type != .cellular
                    ))
                }
                
                monitor.cancel()
                continuation.resume(returning: foundInterfaces)
            }
            
            monitor.start(queue: queue)
            
            // Timeout after 1 second
            queue.asyncAfter(deadline: .now() + 1) {
                monitor.cancel()
                continuation.resume(returning: [])
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func resolveLocalEndpoint(_ endpoint: LocalEndpoint) async throws -> [SocketAddress] {
        var addresses: [SocketAddress] = []
        
        if let port = endpoint.port {
            // If only port is specified, bind to all interfaces
            if endpoint.interface == nil && endpoint.ipAddress == nil {
                addresses.append(.ipv4(address: "0.0.0.0", port: port))
                addresses.append(.ipv6(address: "::", port: port, scopeId: 0))
            } else if let ipAddress = endpoint.ipAddress {
                // Specific IP address
                if ipAddress.contains(":") {
                    addresses.append(.ipv6(address: ipAddress, port: port, scopeId: 0))
                } else {
                    addresses.append(.ipv4(address: ipAddress, port: port))
                }
            }
        }
        
        return addresses
    }
    
    private func resolveRemoteEndpoint(_ endpoint: RemoteEndpoint) async throws -> [SocketAddress] {
        var addresses: [SocketAddress] = []
        
        let port = endpoint.port ?? 443
        
        if let hostName = endpoint.hostName {
            // Use NWEndpoint.Host for DNS resolution
            _ = NWEndpoint.Host(hostName)
            
            // This is a simplified version - real implementation would do proper DNS resolution
            if let ipAddress = endpoint.ipAddress {
                if ipAddress.contains(":") {
                    addresses.append(.ipv6(address: ipAddress, port: port, scopeId: 0))
                } else {
                    addresses.append(.ipv4(address: ipAddress, port: port))
                }
            } else {
                // Default to indicating hostname needs resolution
                addresses.append(.ipv4(address: hostName, port: port))
            }
        } else if let ipAddress = endpoint.ipAddress {
            if ipAddress.contains(":") {
                addresses.append(.ipv6(address: ipAddress, port: port, scopeId: 0))
            } else {
                addresses.append(.ipv4(address: ipAddress, port: port))
            }
        }
        
        return addresses
    }
    
    private func getInterface(named name: String) async throws -> NetworkInterface? {
        let interfaces = try await getAvailableInterfaces()
        return interfaces.first { $0.name == name }
    }
    
    private func getInterfaceAddresses(_ interface: NWInterface) -> [SocketAddress] {
        // This would need to use system APIs to get actual addresses
        // For now, return empty array
        return []
    }
}


#endif