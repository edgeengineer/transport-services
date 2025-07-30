//
//  ProtocolTypes.swift
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