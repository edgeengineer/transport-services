//
//  Platform.swift
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

/// Platform-specific implementation of the Transport Services API
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