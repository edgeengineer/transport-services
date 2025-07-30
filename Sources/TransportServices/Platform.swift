//
//  Platform.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

/// Platform-specific implementation of the Transport Services API
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol Platform: Sendable {
    /// Create a connection object for this platform
    func createConnection(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformConnection
    
    /// Create a listener object for this platform
    func createListener(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformListener
    
    /// Perform candidate gathering for endpoint resolution
    func gatherCandidates(preconnection: Preconnection) async throws -> CandidateSet
    
    /// Check if a protocol stack is supported on this platform
    func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool
    
    /// Get available network interfaces
    func getAvailableInterfaces() async throws -> [NetworkInterface]
}

/// Platform-specific connection implementation
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol PlatformConnection: Sendable {
    /// Initiate the connection
    func initiate() async throws
    
    /// Send data over the connection
    func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws
    
    /// Receive data from the connection
    func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext, Bool)
    
    /// Close the connection gracefully
    func close() async
    
    /// Abort the connection immediately
    func abort() async
    
    /// Get connection state
    func getState() -> ConnectionState
    
    /// Set connection properties
    func setProperty(_ property: ConnectionProperty, value: Any) async throws
    
    /// Get connection properties
    func getProperty(_ property: ConnectionProperty) async -> Any?
}

/// Platform-specific listener implementation
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol PlatformListener: Sendable {
    /// Start listening for incoming connections
    func listen() async throws
    
    /// Stop listening
    func stop() async
    
    /// Accept an incoming connection
    func accept() async throws -> any PlatformConnection
}

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

/// Network interface information
public struct NetworkInterface: Sendable {
    public let name: String
    public let index: Int
    public let type: InterfaceType
    public let addresses: [SocketAddress]
    public let isUp: Bool
    public let supportsMulticast: Bool
    
    public enum InterfaceType: Sendable {
        case wifi
        case cellular
        case ethernet
        case loopback
        case other
    }
    
    public init(name: String, index: Int, type: InterfaceType, addresses: [SocketAddress], isUp: Bool, supportsMulticast: Bool) {
        self.name = name
        self.index = index
        self.type = type
        self.addresses = addresses
        self.isUp = isUp
        self.supportsMulticast = supportsMulticast
    }
}

/// Socket address representation
public enum SocketAddress: Sendable {
    case ipv4(address: String, port: UInt16)
    case ipv6(address: String, port: UInt16, scopeId: UInt32)
    case unix(path: String)
}

/// Protocol stack representation
public struct ProtocolStack: Sendable {
    public let layers: [ProtocolLayer]
    
    public init(layers: [ProtocolLayer]) {
        self.layers = layers
    }
}

/// Individual protocol layer
public enum ProtocolLayer: Sendable {
    case tcp
    case udp
    case sctp
    case quic
    case tls
    case http2
    case http3
    case webTransport
    case custom(String)
}

/// Connection properties that can be set/get
public enum ConnectionProperty: Sendable {
    case keepAlive(enabled: Bool, interval: TimeInterval?)
    case noDelay(Bool)
    case connectionTimeout(TimeInterval)
    case retransmissionTimeout(TimeInterval)
    case multipathPolicy(MultipathPolicy)
    case priority(Int)
    case trafficClass(TrafficClass)
    case receiveBufferSize(Int)
    case sendBufferSize(Int)
}

/// Traffic class for QoS
public enum TrafficClass: Sendable {
    case background
    case bestEffort
    case video
    case voice
    case controlTraffic
}
