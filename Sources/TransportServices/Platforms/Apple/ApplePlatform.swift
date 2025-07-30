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

#if canImport(Network)
import Network

/// Apple platform implementation using Network.framework
public final class ApplePlatform: Platform {
    
    public init() {}
    
    public func createConnection(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformConnection {
        return AppleConnection(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    public func createListener(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformListener {
        return AppleListener(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    // Support for Rendezvous connections (RFC 9622 Section 7.3)
    public func createRendezvous(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) async throws -> (any PlatformConnection, any PlatformListener) {
        // For rendezvous, we need both outgoing connection attempts and incoming listener
        
        // Create a listener for incoming connections
        let listener = AppleListener(preconnection: preconnection, eventHandler: eventHandler)
        
        // Create a connection for outgoing attempts
        let connection = AppleConnection(preconnection: preconnection, eventHandler: eventHandler)
        
        // Start the listener
        try await listener.listen()
        
        // Start connection attempts to remote endpoints
        // Note: Full ICE-style connectivity checks would require more implementation
        Task {
            do {
                try await connection.initiate()
            } catch {
                // Connection might fail if peer connects to us first
                // This is expected in rendezvous scenarios
            }
        }
        
        return (connection, listener)
    }
    
    public func gatherCandidates(preconnection: Preconnection) async throws -> CandidateSet {
        var localCandidates: [LocalCandidate] = []
        var remoteCandidates: [RemoteCandidate] = []
        
        // Gather local candidates
        for localEndpoint in preconnection.localEndpoints {
            let candidate = try await resolveLocalEndpoint(localEndpoint)
            localCandidates.append(candidate)
        }
        
        // Gather remote candidates
        for (index, remoteEndpoint) in preconnection.remoteEndpoints.enumerated() {
            let candidate = try await resolveRemoteEndpoint(remoteEndpoint, priority: index)
            remoteCandidates.append(candidate)
        }
        
        return CandidateSet(localCandidates: localCandidates, remoteCandidates: remoteCandidates)
    }
    
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        // Check if Network.framework supports the requested protocol stack
        for layer in stack.layers {
            switch layer {
            case .tcp, .udp, .tls:
                continue // Supported
            case .quic:
                if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
                    continue // QUIC is supported in newer versions
                } else {
                    return false
                }
            case .http2, .http3:
                // These would need to be implemented on top
                return false
            default:
                return false
            }
        }
        return true
    }
    
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "interface.query")
            
            monitor.pathUpdateHandler = { path in
                var interfaces: [NetworkInterface] = []
                
                for interface in path.availableInterfaces {
                    let addresses = self.getInterfaceAddresses(interface: interface)
                    
                    let networkInterface = NetworkInterface(
                        name: interface.name,
                        index: 0, // TODO: Get actual interface index
                        type: self.convertInterfaceType(interface.type),
                        addresses: addresses,
                        isUp: true, // NWPath only shows available interfaces
                        supportsMulticast: interface.type != .loopback
                    )
                    interfaces.append(networkInterface)
                }
                
                monitor.cancel()
                continuation.resume(returning: interfaces)
            }
            
            monitor.start(queue: queue)
        }
    }
    
    // MARK: - Private Methods
    
    private func convertInterfaceType(_ type: NWInterface.InterfaceType) -> NetworkInterface.InterfaceType {
        switch type {
        case .wifi:
            return .wifi
        case .wiredEthernet:
            return .ethernet
        case .cellular:
            return .cellular
        case .loopback:
            return .loopback
        default:
            return .other
        }
    }
    
    private func resolveLocalEndpoint(_ endpoint: LocalEndpoint) async throws -> LocalCandidate {
        // For local endpoints, we primarily need to validate the interface
        var resolvedAddresses: [SocketAddress] = []
        
        if let interfaceName = endpoint.interface {
            // Validate that the interface exists
            let interfaces = try await getAvailableInterfaces()
            guard interfaces.contains(where: { $0.name == interfaceName }) else {
                throw TransportError.invalidInterface
            }
        }
        
        // If a specific address is provided, use it
        if let ipAddress = endpoint.ipAddress {
            let port = endpoint.port ?? 0
            if ipAddress.contains(":") {
                // IPv6
                resolvedAddresses.append(.ipv6(address: ipAddress, port: port, scopeId: 0))
            } else {
                // IPv4
                resolvedAddresses.append(.ipv4(address: ipAddress, port: port))
            }
        }
        
        return LocalCandidate(
            endpoint: endpoint,
            addresses: resolvedAddresses,
            interface: nil
        )
    }
    
    private func resolveRemoteEndpoint(_ endpoint: RemoteEndpoint, priority: Int) async throws -> RemoteCandidate {
        var resolvedAddresses: [SocketAddress] = []
        
        if let ipAddress = endpoint.ipAddress, let port = endpoint.port {
            // Direct IP address provided
            if ipAddress.contains(":") {
                resolvedAddresses.append(.ipv6(address: ipAddress, port: port, scopeId: 0))
            } else {
                resolvedAddresses.append(.ipv4(address: ipAddress, port: port))
            }
        } else if let hostName = endpoint.hostName, let port = endpoint.port {
            // Need to resolve hostname
            resolvedAddresses = try await resolveHostname(hostName, port: port)
        }
        
        return RemoteCandidate(
            endpoint: endpoint,
            addresses: resolvedAddresses,
            priority: priority
        )
    }
    
    private func resolveHostname(_ hostname: String, port: UInt16) async throws -> [SocketAddress] {
        actor ResolutionState {
            var hasResolved = false
            
            func checkAndSetResolved() -> Bool {
                if hasResolved { return true }
                hasResolved = true
                return false
            }
        }
        
        // Use DNS resolution via getaddrinfo or similar
        // For now, use a simplified approach with NWConnection
        return try await withCheckedThrowingContinuation { continuation in
            let host = NWEndpoint.Host(hostname)
            let port = NWEndpoint.Port(integerLiteral: port)
            
            // Create a dummy connection just for DNS resolution
            let params = NWParameters.udp
            let connection = NWConnection(host: host, port: port, using: params)
            
            let state = ResolutionState()
            
            // Add timeout to prevent indefinite hanging
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                Task {
                    guard await !state.checkAndSetResolved() else { return }
                    connection.cancel()
                    continuation.resume(throwing: TransportError.establishmentTimeout)
                }
            }
            
            connection.stateUpdateHandler = { connectionState in
                Task {
                    guard await !state.checkAndSetResolved() else { 
                        timeoutTask.cancel()
                        return 
                    }
                    
                    switch connectionState {
                    case .ready:
                        timeoutTask.cancel()
                        // Extract resolved addresses from the connection path
                        var addresses: [SocketAddress] = []
                        
                        if let endpoint = connection.currentPath?.remoteEndpoint {
                            switch endpoint {
                            case let .hostPort(host: resolvedHost, port: resolvedPort):
                                switch resolvedHost {
                                case let .ipv4(address):
                                    addresses.append(.ipv4(
                                        address: "\(address)",
                                        port: UInt16(resolvedPort.rawValue)
                                    ))
                                case let .ipv6(address):
                                    addresses.append(.ipv6(
                                        address: "\(address)",
                                        port: UInt16(resolvedPort.rawValue),
                                        scopeId: 0
                                    ))
                                case .name:
                                    // Should not happen after resolution
                                    continuation.resume(throwing: TransportError.resolutionFailed)
                                    return
                                @unknown default:
                                    break
                                }
                            default:
                                break
                            }
                        }
                        
                        connection.cancel()
                        
                        if addresses.isEmpty {
                            continuation.resume(throwing: TransportError.resolutionFailed)
                        } else {
                            continuation.resume(returning: addresses)
                        }
                        
                    case let .failed(error):
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(throwing: error)
                        
                    case .waiting:
                        // Network might not be available - continue waiting but timeout will catch it
                        break
                        
                    default:
                        break
                    }
                }
            }
            
            connection.start(queue: DispatchQueue(label: "dns.resolution"))
        }
    }
    
    private func getInterfaceAddresses(interface: NWInterface) -> [SocketAddress] {
        // Network.framework doesn't directly expose interface addresses
        // We would need to use lower-level APIs like getifaddrs() for full implementation
        // For now, return common addresses based on interface type
        var addresses: [SocketAddress] = []
        
        switch interface.type {
        case .loopback:
            // Loopback typically has 127.0.0.1 and ::1
            addresses.append(.ipv4(address: "127.0.0.1", port: 0))
            addresses.append(.ipv6(address: "::1", port: 0, scopeId: 0))
        default:
            // For other interfaces, we can't determine addresses without lower-level APIs
            // This would require importing Darwin and using getifaddrs
            break
        }
        
        return addresses
    }
}

#endif
