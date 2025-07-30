//
//  Connection.swift
//  
//
//  Maximilian Alexander
//

import Foundation

public actor Connection {
    public let preconnection: Preconnection
    private var state: ConnectionState = .establishing

    public init(preconnection: Preconnection) {
        self.preconnection = preconnection
    }

    // Connection Lifecycle
    public func start() {
        // Placeholder for implementation
    }

    public func close() {
        // Placeholder for implementation
    }

    public func abort() {
        // Placeholder for implementation
    }

    public func clone() -> Connection {
        // Placeholder for implementation
        return Connection(preconnection: self.preconnection)
    }

    // Data Transfer
    public func send(data: Data, context: MessageContext? = nil, endOfMessage: Bool = true) {
        // Placeholder for implementation
    }

    public func receive(minIncompleteLength: Int? = nil, maxLength: Int? = nil) {
        // Placeholder for implementation
    }

    // Properties
    public func getProperties() -> TransportProperties {
        // Placeholder for implementation
        return self.preconnection.transportProperties
    }

    public func setProperty(property: Any, value: Any) {
        // Placeholder for implementation
    }
    
    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // Placeholder for implementation
    }

    public func removeRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // Placeholder for implementation
    }
    
    public func addLocal(_ localEndpoints: [LocalEndpoint]) {
        // Placeholder for implementation
    }

    public func removeLocal(_ localEndpoints: [LocalEndpoint]) {
        // Placeholder for implementation
    }
}
