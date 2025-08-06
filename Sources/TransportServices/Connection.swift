//
//  Connection.swift
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

/// Represents an established or establishing transport connection
/// Based on RFC 9622 Section 3
public protocol Connection: Sendable {
    /// The preconnection used to create this connection
    var preconnection: Preconnection { get }
    
    /// Event handler for transport events
    var eventHandler: @Sendable (TransportServicesEvent) -> Void { get }
    
    /// Current state of the connection
    var state: ConnectionState { get }
    
    /// Transport properties for this connection
    var properties: TransportProperties { get }
    
    /// The connection group this connection belongs to
    var group: ConnectionGroup? { get }
    
    /// Set the connection group
    func setGroup(_ group: ConnectionGroup?)
    
    // MARK: - Connection Lifecycle
    
    /// Close the connection gracefully
    func close()
    
    /// Abort the connection immediately
    func abort()
    
    /// Clone this connection to create a new connection with same properties
    func clone() throws -> any Connection
    
    // MARK: - Data Transfer
    
    /// Send data over the connection
    func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws
    
    /// Receive data from the connection
    func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext)
    
    /// Start receiving data continuously
    func startReceiving(minIncompleteLength: Int?, maxLength: Int?) async
    
    // MARK: - Endpoint Management
    
    /// Add remote endpoints for multipath or migration
    func addRemote(_ remoteEndpoints: [RemoteEndpoint])
    
    /// Remove remote endpoints
    func removeRemote(_ remoteEndpoints: [RemoteEndpoint])
    
    /// Add local endpoints for multipath or migration
    func addLocal(_ localEndpoints: [LocalEndpoint])
    
    /// Remove local endpoints
    func removeLocal(_ localEndpoints: [LocalEndpoint])
}

/// Default implementations for Connection protocol
public extension Connection {
    func send(data: Data, context: MessageContext = MessageContext(), endOfMessage: Bool = true) async throws {
        try await send(data: data, context: context, endOfMessage: endOfMessage)
    }
    
    func receive(minIncompleteLength: Int? = nil, maxLength: Int? = nil) async throws -> (Data, MessageContext) {
        try await receive(minIncompleteLength: minIncompleteLength, maxLength: maxLength)
    }
    
    func startReceiving(minIncompleteLength: Int? = nil, maxLength: Int? = nil) async {
        await startReceiving(minIncompleteLength: minIncompleteLength, maxLength: maxLength)
    }
}

/// Connection group scheduler for managing multiple connections
public protocol ConnectionGroupScheduler: AnyObject {
    func schedule(data: Data, context: MessageContext, group: ConnectionGroup) async -> (any Connection)?
}
