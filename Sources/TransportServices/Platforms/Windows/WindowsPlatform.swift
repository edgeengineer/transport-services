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
        let candidateSet = CandidateSet()
        
        // Resolve remote endpoints
        for remoteEndpoint in preconnection.remoteEndpoints {
            if let hostname = remoteEndpoint.hostName {
                // Resolve hostname to IP addresses
                let socketType = preconnection.transportProperties.reliability == .require
                    ? WindowsCompat.SOCK_STREAM
                    : WindowsCompat.SOCK_DGRAM
                
                let addresses = try await WindowsCompat.resolveHostname(hostname, type: socketType)
                
                for address in addresses {
                    let candidate = PathCandidate(
                        localEndpoint: preconnection.localEndpoints.first,
                        remoteEndpoint: RemoteEndpoint(ipAddress: address, port: remoteEndpoint.port),
                        protocolStack: createProtocolStack(for: preconnection.transportProperties),
                        interfaceName: nil
                    )
                    candidateSet.addCandidate(candidate)
                }
            } else if let ipAddress = remoteEndpoint.ipAddress {
                // Direct IP address
                let candidate = PathCandidate(
                    localEndpoint: preconnection.localEndpoints.first,
                    remoteEndpoint: remoteEndpoint,
                    protocolStack: createProtocolStack(for: preconnection.transportProperties),
                    interfaceName: nil
                )
                candidateSet.addCandidate(candidate)
            }
        }
        
        return candidateSet
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

// MARK: - Path Candidate

/// Represents a candidate path for connection establishment
private class PathCandidate {
    let localEndpoint: LocalEndpoint?
    let remoteEndpoint: RemoteEndpoint
    let protocolStack: ProtocolStack
    let interfaceName: String?
    
    init(localEndpoint: LocalEndpoint?, remoteEndpoint: RemoteEndpoint, protocolStack: ProtocolStack, interfaceName: String?) {
        self.localEndpoint = localEndpoint
        self.remoteEndpoint = remoteEndpoint
        self.protocolStack = protocolStack
        self.interfaceName = interfaceName
    }
}

// MARK: - Candidate Set

/// Collection of path candidates for connection establishment
private class CandidateSet {
    private var candidates: [PathCandidate] = []
    
    func addCandidate(_ candidate: PathCandidate) {
        candidates.append(candidate)
    }
    
    func getCandidates() -> [PathCandidate] {
        return candidates
    }
    
    func isEmpty() -> Bool {
        return candidates.isEmpty
    }
}

#endif
