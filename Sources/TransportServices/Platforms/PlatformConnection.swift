//
//  PlatformConnection.swift
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

/// Platform-specific connection implementation
public protocol PlatformConnection: Sendable {
    /// Initiate the connection
    func initiate() async throws
    
    /// Send data over the connection
    func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws
    
    /// Receive data from the connection
    func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext, Bool)
    
    /// Close the connection gracefully
    func close() async
    
    /// Abort the connection immediately
    func abort() async
    
    /// Get connection state
    func getState() async -> ConnectionState
    
    /// Set the owner connection for proper event handling
    func setOwnerConnection(_ connection: Connection?) async
}