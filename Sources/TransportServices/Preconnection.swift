//
//  Preconnection.swift
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

/// Represents a potential connection before it is established
/// Based on RFC 9622 Section 6
public protocol Preconnection: Sendable {
    /// Local endpoints for this preconnection
    var localEndpoints: [LocalEndpoint] { get set }
    
    /// Remote endpoints for this preconnection
    var remoteEndpoints: [RemoteEndpoint] { get set }
    
    /// Transport properties for this preconnection
    var transportProperties: TransportProperties { get set }
    
    /// Security parameters for this preconnection
    var securityParameters: SecurityParameters { get set }
    
    /// Resolve endpoint candidates for both local and remote endpoints
    func resolve() async -> (local: [LocalEndpoint], remote: [RemoteEndpoint])
    
    /// Initiate a connection to a remote endpoint
    func initiate(timeout: TimeInterval?, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Connection
    
    /// Initiate a connection with initial data
    func initiateWithSend(messageData: Data, messageContext: MessageContext, timeout: TimeInterval?, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Connection
    
    /// Listen for incoming connections
    func listen(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Listener
    
    /// Establish a peer-to-peer connection using rendezvous
    func rendezvous(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> (any Connection, any Listener)
    
    /// Add remote endpoints for multipath or migration
    mutating func addRemote(_ remoteEndpoints: [RemoteEndpoint])
}

/// Default implementations for convenience methods
public extension Preconnection {
    func initiate(timeout: TimeInterval? = nil, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil) async throws -> any Connection {
        try await initiate(timeout: timeout, eventHandler: eventHandler)
    }
    
    func initiateWithSend(messageData: Data, messageContext: MessageContext = MessageContext(), timeout: TimeInterval? = nil, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil) async throws -> any Connection {
        try await initiateWithSend(messageData: messageData, messageContext: messageContext, timeout: timeout, eventHandler: eventHandler)
    }
    
    func listen(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil) async throws -> any Listener {
        try await listen(eventHandler: eventHandler)
    }
    
    func rendezvous(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil) async throws -> (any Connection, any Listener) {
        try await rendezvous(eventHandler: eventHandler)
    }
}