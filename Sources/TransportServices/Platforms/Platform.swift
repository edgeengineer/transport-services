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
    func createConnection(preconnection: any Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any Connection
    
    /// Perform candidate gathering for endpoint resolution
    func gatherCandidates(preconnection: any Preconnection) async throws -> CandidateSet
    
    /// Check if a protocol stack is supported on this platform
    func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool
    
    /// Get available network interfaces
    func getAvailableInterfaces() async throws -> [NetworkInterface]
}