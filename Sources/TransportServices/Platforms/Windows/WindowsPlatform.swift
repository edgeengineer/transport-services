//
//  WindowsPlatform.swift
//  
//
//  Maximilian Alexander
//

#if os(Windows)
import WinSDK
import Foundation

/// Windows platform implementation using IOCP
public final class WindowsPlatform: Platform {
    
    public init() {
        // Initialize Winsock on platform initialization
        WindowsCompat.initializeWinsock()
    }
    
    public func createConnection(preconnection: any Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Connection {
        // Create a Windows-specific connection
        if let windowsPreconnection = preconnection as? WindowsPreconnection {
            return WindowsConnection(preconnection: windowsPreconnection, eventHandler: eventHandler)
        } else {
            // Create a new Windows preconnection from the generic one
            let windowsPreconnection = WindowsPreconnection(
                localEndpoints: preconnection.localEndpoints,
                remoteEndpoints: preconnection.remoteEndpoints,
                transportProperties: preconnection.transportProperties,
                securityParameters: preconnection.securityParameters
            )
            return WindowsConnection(preconnection: windowsPreconnection, eventHandler: eventHandler)
        }
    }
    
    public func gatherCandidates(preconnection: any Preconnection) async throws -> CandidateSet {
        var localCandidates: [LocalCandidate] = []
        var remoteCandidates: [RemoteCandidate] = []
        
        // Gather local candidates
        for localEndpoint in preconnection.localEndpoints {
            let addresses: [SocketAddress] = [] // TODO: Resolve local addresses
            let candidate = LocalCandidate(
                endpoint: localEndpoint,
                addresses: addresses,
                interface: nil
            )
            localCandidates.append(candidate)
        }
        
        // Gather remote candidates
        for remoteEndpoint in preconnection.remoteEndpoints {
            var addresses: [SocketAddress] = []
            
            if let hostname = remoteEndpoint.hostName {
                // Resolve hostname to IP addresses
                let socketType = preconnection.transportProperties.reliability == .require
                    ? WindowsCompat.SOCK_STREAM
                    : WindowsCompat.SOCK_DGRAM
                
                let resolvedAddresses = try await WindowsCompat.resolveHostname(hostname, type: socketType)
                
                for address in resolvedAddresses {
                    // Create SocketAddress from resolved IP
                    // TODO: Detect IPv4 vs IPv6
                    let socketAddr = SocketAddress.ipv4(address: address, port: remoteEndpoint.port ?? 0)
                    addresses.append(socketAddr)
                }
            } else if let ipAddress = remoteEndpoint.ipAddress {
                // Direct IP address
                // TODO: Detect IPv4 vs IPv6
                let socketAddr = SocketAddress.ipv4(address: ipAddress, port: remoteEndpoint.port ?? 0)
                addresses.append(socketAddr)
            }
            
            let candidate = RemoteCandidate(
                endpoint: remoteEndpoint,
                addresses: addresses,
                priority: 0
            )
            remoteCandidates.append(candidate)
        }
        
        return CandidateSet(localCandidates: localCandidates, remoteCandidates: remoteCandidates)
    }
    
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        // Windows with IOCP supports TCP and UDP
        for layer in stack.layers {
            switch layer {
            case .tcp, .udp:
                continue
            case .tls:
                // Would use SChannel (not yet implemented)
                continue
            default:
                return false
            }
        }
        return true
    }
    
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        return try WindowsCompat.getNetworkInterfaces()
    }
    
    // MARK: - Private Helper Methods
    
    private func createProtocolStack(for properties: TransportProperties) -> ProtocolStack {
        var layers: [ProtocolLayer] = []
        
        // Add transport layer
        if properties.reliability == .require {
            layers.append(.tcp)
        } else {
            layers.append(.udp)
        }
        
        // Add security layer if needed (future implementation)
        // if properties.requiresEncryption {
        //     layers.append(.tls)
        // }
        
        return ProtocolStack(layers: layers)
    }
}


#endif
