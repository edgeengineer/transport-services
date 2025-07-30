//
//  MessageContext.swift
//  
//
//  Maximilian Alexander
//

import Foundation

public struct MessageContext: Sendable {
    // Message Properties (RFC 9622 Section 9.1.3)
    public var lifetime: TimeInterval? // Infinite represented by nil
    public var priority: UInt = 100
    public var ordered: Bool = true
    public var safelyReplayable: Bool = false
    public var final: Bool = false
    public var checksumLen: Int? // Full Coverage represented by nil
    public var reliable: Bool = true
    public var capacityProfile: CapacityProfile? // Inherited from connection by default
    public var noFragmentation: Bool = false
    public var noSegmentation: Bool = false

    // Read-Only Properties
    public private(set) var remoteEndpoint: RemoteEndpoint?
    public private(set) var localEndpoint: LocalEndpoint?
    public private(set) var ecn: UInt8?
    public private(set) var isEarlyData: Bool = false
    public private(set) var isFinal: Bool = false

    public init() {}
}
