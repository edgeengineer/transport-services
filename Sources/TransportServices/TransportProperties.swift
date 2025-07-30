//
//  TransportProperties.swift
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

public struct TransportProperties: Sendable {
    // Selection Properties (RFC 9622 Section 6.2)
    public var reliability: Preference = .require
    public var preserveMsgBoundaries: Preference = .noPreference
    public var perMsgReliability: Preference = .noPreference
    public var preserveOrder: Preference = .require
    public var zeroRttMsg: Preference = .noPreference
    public var multistreaming: Preference = .prefer
    public var fullChecksumSend: Preference = .require
    public var fullChecksumRecv: Preference = .require
    public var congestionControl: Preference = .require
    public var keepAlive: Preference = .noPreference
    public var interface: [(Preference, String)] = []
    public var pvd: [(Preference, String)] = []
    public var useTemporaryLocalAddress: Preference = .prefer
    public var multipath: Multipath = .disabled
    public var advertisesAltaddr: Bool = false
    public var direction: Direction = .bidirectional
    public var softErrorNotify: Preference = .noPreference
    public var activeReadBeforeSend: Preference = .noPreference

    // Connection Properties (RFC 9622 Section 8.1)
    public var recvChecksumLen: Int? // Full Coverage represented by nil
    public var connPriority: UInt = 100
    public var connTimeout: TimeInterval? // Disabled represented by nil
    public var keepAliveTimeout: TimeInterval? // Disabled represented by nil
    public var connScheduler: Scheduler = .weightedFairQueueing
    public var connCapacityProfile: CapacityProfile = .default
    public var multipathPolicy: MultipathPolicy = .handover
    public var minSendRate: UInt? // Unlimited represented by nil
    public var minRecvRate: UInt? // Unlimited represented by nil
    public var maxSendRate: UInt? // Unlimited represented by nil
    public var maxRecvRate: UInt? // Unlimited represented by nil
    public var groupConnLimit: UInt? // Unlimited represented by nil
    public var isolateSession: Bool = false

    // TCP-Specific Properties (RFC 9622 Section 8.2)
    public struct Tcp: Sendable {
        public var userTimeoutValue: UInt?
        public var userTimeoutEnabled: Bool = false
        public var userTimeoutChangeable: Bool = true
    }
    public var tcp: Tcp = Tcp()

    public init() {}
}
