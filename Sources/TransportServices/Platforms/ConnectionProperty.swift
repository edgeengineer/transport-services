//
//  ConnectionProperty.swift
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