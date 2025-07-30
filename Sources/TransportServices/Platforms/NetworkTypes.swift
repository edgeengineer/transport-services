//
//  NetworkTypes.swift
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