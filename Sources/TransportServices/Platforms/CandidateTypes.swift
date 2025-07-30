//
//  CandidateTypes.swift
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

/// Represents a set of connection candidates after gathering
public struct CandidateSet: Sendable {
    public let localCandidates: [LocalCandidate]
    public let remoteCandidates: [RemoteCandidate]
    
    public init(localCandidates: [LocalCandidate], remoteCandidates: [RemoteCandidate]) {
        self.localCandidates = localCandidates
        self.remoteCandidates = remoteCandidates
    }
}

/// Local endpoint candidate with resolved addresses
public struct LocalCandidate: Sendable {
    public let endpoint: LocalEndpoint
    public let addresses: [SocketAddress]
    public let interface: NetworkInterface?
    
    public init(endpoint: LocalEndpoint, addresses: [SocketAddress], interface: NetworkInterface?) {
        self.endpoint = endpoint
        self.addresses = addresses
        self.interface = interface
    }
}

/// Remote endpoint candidate with resolved addresses
public struct RemoteCandidate: Sendable {
    public let endpoint: RemoteEndpoint
    public let addresses: [SocketAddress]
    public let priority: Int
    
    public init(endpoint: RemoteEndpoint, addresses: [SocketAddress], priority: Int) {
        self.endpoint = endpoint
        self.addresses = addresses
        self.priority = priority
    }
}