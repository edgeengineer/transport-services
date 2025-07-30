//
//  TapsTypes.swift
//  
//
//  Maximilian Alexander
//

import Foundation

// From RFC 9622 Section 6.2
public enum Preference: Sendable {
    case require
    case prefer
    case noPreference
    case avoid
    case prohibit
}

// From RFC 9622 Section 6.2.14
public enum Multipath: Sendable {
    case disabled
    case active
    case passive
}

// From RFC 9622 Section 6.2.16
public enum Direction: Sendable {
    case bidirectional
    case unidirectionalSend
    case unidirectionalReceive
}

// From RFC 9622 Section 8.1.6
public enum CapacityProfile: Sendable {
    case `default`
    case scavenger
    case lowLatencyInteractive
    case lowLatencyNonInteractive
    case constantRateStreaming
    case capacitySeeking
}

// From RFC 9622 Section 8.1.7
public enum MultipathPolicy: Sendable {
    case handover
    case interactive
    case aggregate
}

// From RFC 9622 Section 8.1.5
public enum Scheduler: Sendable {
    case weightedFairQueueing
}

// From RFC 9622 Section 8.1.11.1
public enum ConnectionState: Sendable {
    case establishing
    case established
    case closing
    case closed
}
