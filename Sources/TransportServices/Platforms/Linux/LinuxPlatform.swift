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
        var candidates = CandidateSet()
        
        // Get available interfaces
        let interfaces = try await getAvailableInterfaces()
        
        // For each interface, create path candidates
        for interface in interfaces {
            // Create candidates for each protocol stack
            if preconnection.transportProperties.reliability == .require {
                // TCP candidates
                let tcpCandidate = PathCandidate(
                    interface: interface,
                    remoteEndpoint: preconnection.remoteEndpoints.first,
                    protocolStack: ProtocolStack(layers: [.tcp])
                )
                candidates.pathCandidates.append(tcpCandidate)
            } else if preconnection.transportProperties.reliability == .prohibit {
                // UDP candidates
                let udpCandidate = PathCandidate(
                    interface: interface,
                    remoteEndpoint: preconnection.remoteEndpoints.first,
                    protocolStack: ProtocolStack(layers: [.udp])
                )
                candidates.pathCandidates.append(udpCandidate)
            } else {
                // Both TCP and UDP candidates
                let tcpCandidate = PathCandidate(
                    interface: interface,
                    remoteEndpoint: preconnection.remoteEndpoints.first,
                    protocolStack: ProtocolStack(layers: [.tcp])
                )
                let udpCandidate = PathCandidate(
                    interface: interface,
                    remoteEndpoint: preconnection.remoteEndpoints.first,
                    protocolStack: ProtocolStack(layers: [.udp])
                )
                candidates.pathCandidates.append(tcpCandidate)
                candidates.pathCandidates.append(udpCandidate)
            }
        }
        
        return candidates
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
                    type = .wired
                } else if name.hasPrefix("wlan") || name.hasPrefix("wl") {
                    type = .wifi
                } else {
                    type = .other
                }
                
                // Get addresses for this interface
                var addresses: [String] = []
                var tempCurrent = ifaddrs
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
                                    addresses.append(String(cString: ipBuffer))
                                }
                            } else if addr.pointee.sa_family == sa_family_t(AF_INET6) {
                                // IPv6 address
                                let sockaddrIn6 = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                                var ipBuffer = Array<CChar>(repeating: 0, count: Int(INET6_ADDRSTRLEN))
                                var mutableAddr = sockaddrIn6.sin6_addr
                                if inet_ntop(AF_INET6, &mutableAddr, &ipBuffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                                    addresses.append(String(cString: ipBuffer))
                                }
                            }
                        }
                    }
                    tempCurrent = tempInterface.pointee.ifa_next
                }
                
                let networkInterface = NetworkInterface(
                    name: name,
                    type: type,
                    addresses: addresses
                )
                interfaces.append(networkInterface)
                seenInterfaces.insert(name)
            }
            
            current = interface.pointee.ifa_next
        }
        
        return interfaces
    }
}

/// Network interface information
public struct NetworkInterface: Sendable {
    public let name: String
    public let type: InterfaceType
    public let addresses: [String]
    
    public enum InterfaceType: Sendable {
        case wifi
        case wired
        case cellular
        case loopback
        case other
    }
}

/// Candidate set for path selection
public struct CandidateSet: Sendable {
    public var pathCandidates: [PathCandidate] = []
    
    public init() {}
}

/// Path candidate for connection establishment
public struct PathCandidate: Sendable {
    public let interface: NetworkInterface
    public let remoteEndpoint: RemoteEndpoint?
    public let protocolStack: ProtocolStack
    
    public init(interface: NetworkInterface, remoteEndpoint: RemoteEndpoint?, protocolStack: ProtocolStack) {
        self.interface = interface
        self.remoteEndpoint = remoteEndpoint
        self.protocolStack = protocolStack
    }
}

/// Protocol stack definition
public struct ProtocolStack: Sendable {
    public let layers: [ProtocolLayer]
    
    public init(layers: [ProtocolLayer]) {
        self.layers = layers
    }
}

/// Protocol layer enumeration
public enum ProtocolLayer: Sendable {
    case tcp
    case udp
    case tls
    case quic
    case sctp
    case custom(String)
}

#endif
