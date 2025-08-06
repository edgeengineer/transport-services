//
//  LinuxPlatform.swift
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

#if os(Linux)
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#else
#error("Unsupported C library")
#endif

/// Linux platform implementation using epoll and BSD sockets
public final class LinuxPlatform: Platform {
    
    public init() {}
    
    public func createConnection(preconnection: any Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Connection {
        // Create a Linux-specific connection
        return LinuxConnection(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    public func createListener(preconnection: any Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Listener {
        // Create a Linux-specific listener
        return LinuxListener(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    public func createPreconnection(localEndpoints: [LocalEndpoint] = [],
                                   remoteEndpoints: [RemoteEndpoint] = [],
                                   transportProperties: TransportProperties = TransportProperties(),
                                   securityParameters: SecurityParameters = SecurityParameters()) -> any Preconnection {
        return LinuxPreconnection(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            transportProperties: transportProperties,
            securityParameters: securityParameters
        )
    }
    
    public func gatherCandidates(preconnection: any Preconnection) async throws -> CandidateSet {
        // Gather network path candidates for Linux
        var localCandidates: [LocalCandidate] = []
        var remoteCandidates: [RemoteCandidate] = []
        
        // Get available interfaces
        let interfaces = try await getAvailableInterfaces()
        
        // Create local candidates from interfaces and local endpoints
        for localEndpoint in preconnection.localEndpoints {
            // Find matching interface or use all interfaces
            let matchingInterfaces = localEndpoint.interface != nil
                ? interfaces.filter { $0.name == localEndpoint.interface }
                : interfaces
            
            for interface in matchingInterfaces {
                // Use the interface addresses directly - they're already SocketAddress
                let localCandidate = LocalCandidate(
                    endpoint: localEndpoint,
                    addresses: interface.addresses,
                    interface: interface
                )
                localCandidates.append(localCandidate)
            }
        }
        
        // If no local endpoints specified, create candidates from all interfaces
        if preconnection.localEndpoints.isEmpty {
            for interface in interfaces {
                let localEndpoint = LocalEndpoint()
                let localCandidate = LocalCandidate(
                    endpoint: localEndpoint,
                    addresses: interface.addresses,
                    interface: interface
                )
                localCandidates.append(localCandidate)
            }
        }
        
        // Create remote candidates from remote endpoints
        for (index, remoteEndpoint) in preconnection.remoteEndpoints.enumerated() {
            // For now, create a simple remote candidate
            // In real implementation would resolve hostnames to addresses
            var addresses: [SocketAddress] = []
            
            if let ipAddress = remoteEndpoint.ipAddress {
                let port = remoteEndpoint.port ?? 0
                if ipAddress.contains(":") {
                    addresses.append(.ipv6(address: ipAddress, port: port, scopeId: 0))
                } else {
                    addresses.append(.ipv4(address: ipAddress, port: port))
                }
            }
            
            let remoteCandidate = RemoteCandidate(
                endpoint: remoteEndpoint,
                addresses: addresses,
                priority: index
            )
            remoteCandidates.append(remoteCandidate)
        }
        
        return CandidateSet(localCandidates: localCandidates, remoteCandidates: remoteCandidates)
    }
    
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        // Linux with epoll/sockets supports TCP and UDP
        for layer in stack.layers {
            switch layer {
            case .tcp, .udp:
                continue
            case .tls:
                // TLS would require OpenSSL or similar integration
                // For now, mark as unsupported
                return false
            case .quic:
                // QUIC would require a QUIC library
                return false
            case .sctp:
                // SCTP is supported on Linux but not implemented yet
                return false
            default:
                return false
            }
        }
        return true
    }
    
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        
        // Get interface information using getifaddrs
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else {
            throw LinuxTransportError.resolutionFailed
        }
        defer { freeifaddrs(ifaddrs) }
        
        var current = ifaddrs
        var seenInterfaces = Set<String>()
        
        while let interface = current {
            let name = String(cString: interface.pointee.ifa_name)
            
            // Skip if we've already processed this interface
            if seenInterfaces.contains(name) {
                current = interface.pointee.ifa_next
                continue
            }
            
            // Check if interface is up
            let flags = Int(interface.pointee.ifa_flags)
            let isUp = (flags & Int(IFF_UP)) != 0
            let isLoopback = (flags & Int(IFF_LOOPBACK)) != 0
            
            if isUp {
                // Get interface type
                let type: NetworkInterface.InterfaceType
                if isLoopback {
                    type = .loopback
                } else if name.hasPrefix("eth") || name.hasPrefix("en") {
                    type = .ethernet
                } else if name.hasPrefix("wlan") || name.hasPrefix("wl") {
                    type = .wifi
                } else {
                    type = .other
                }
                
                // Get addresses for this interface
                var socketAddresses: [SocketAddress] = []
                var tempCurrent = ifaddrs
                var interfaceIndex = 0
                
                while let tempInterface = tempCurrent {
                    let tempName = String(cString: tempInterface.pointee.ifa_name)
                    if tempName == name {
                        if let addr = tempInterface.pointee.ifa_addr {
                            if addr.pointee.sa_family == sa_family_t(AF_INET) {
                                // IPv4 address
                                let sockaddrIn = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                                var ipBuffer = Array<CChar>(repeating: 0, count: Int(INET_ADDRSTRLEN))
                                var mutableAddr = sockaddrIn.sin_addr
                                if inet_ntop(AF_INET, &mutableAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                                    let validLength = ipBuffer.firstIndex(of: 0) ?? ipBuffer.count
                                    let uint8Buffer = ipBuffer[..<validLength].map { UInt8(bitPattern: $0) }
                                    let address = String(decoding: uint8Buffer, as: UTF8.self)
                                    let port = UInt16(bigEndian: sockaddrIn.sin_port)
                                    socketAddresses.append(.ipv4(address: address, port: port))
                                }
                            } else if addr.pointee.sa_family == sa_family_t(AF_INET6) {
                                // IPv6 address
                                let sockaddrIn6 = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                                var ipBuffer = Array<CChar>(repeating: 0, count: Int(INET6_ADDRSTRLEN))
                                var mutableAddr = sockaddrIn6.sin6_addr
                                if inet_ntop(AF_INET6, &mutableAddr, &ipBuffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                                    let validLength = ipBuffer.firstIndex(of: 0) ?? ipBuffer.count
                                    let uint8Buffer = ipBuffer[..<validLength].map { UInt8(bitPattern: $0) }
                                    let address = String(decoding: uint8Buffer, as: UTF8.self)
                                    let port = UInt16(bigEndian: sockaddrIn6.sin6_port)
                                    let scopeId = sockaddrIn6.sin6_scope_id
                                    socketAddresses.append(.ipv6(address: address, port: port, scopeId: scopeId))
                                }
                            }
                        }
                    }
                    tempCurrent = tempInterface.pointee.ifa_next
                }
                
                // Check if interface supports multicast
                let supportsMulticast = (flags & Int(IFF_MULTICAST)) != 0
                
                // Get interface index (simplified - in real implementation would use if_nametoindex)
                interfaceIndex += 1
                
                let networkInterface = NetworkInterface(
                    name: name,
                    index: interfaceIndex,
                    type: type,
                    addresses: socketAddresses,
                    isUp: isUp,
                    supportsMulticast: supportsMulticast
                )
                interfaces.append(networkInterface)
                seenInterfaces.insert(name)
            }
            
            current = interface.pointee.ifa_next
        }
        
        return interfaces
    }
}

// Network interface, CandidateSet, ProtocolStack and ProtocolLayer types are defined in common platform files

#endif
