//
//  EventCollector.swift
//  
//
//  Test utility for collecting events from TransportServices asynchronously
//

import Foundation
@testable import TransportServices

/// Helper actor to collect events in tests
actor EventCollector {
    private var collectedEvents: [TransportServicesEvent] = []
    
    init() {}
    
    public func add(_ event: TransportServicesEvent) {
        collectedEvents.append(event)
    }
    
    public var events: [TransportServicesEvent] {
        collectedEvents
    }
    
    public func clear() {
        collectedEvents.removeAll()
    }
    
    public func hasEvent(matching predicate: (TransportServicesEvent) -> Bool) -> Bool {
        collectedEvents.contains(where: predicate)
    }
    
    public func waitForEvent(matching predicate: @escaping (TransportServicesEvent) -> Bool, timeout: Duration = .seconds(5)) async throws -> TransportServicesEvent? {
        let deadline = ContinuousClock.now + timeout
        
        while ContinuousClock.now < deadline {
            if let event = collectedEvents.first(where: predicate) {
                return event
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        return nil
    }
}

/// Helper for connection state assertions
extension EventCollector {
    func hasReadyEvent() -> Bool {
        hasEvent { event in
            if case .ready = event { return true }
            return false
        }
    }
    
    func hasClosedEvent() -> Bool {
        hasEvent { event in
            if case .closed = event { return true }
            return false
        }
    }
    
    func hasConnectionReceivedEvent() -> Bool {
        hasEvent { event in
            if case .connectionReceived = event { return true }
            return false
        }
    }
}