//
//  Preconnection.swift
//  
//
//  Maximilian Alexander
//

import Foundation

public struct Preconnection: Sendable {
    public var localEndpoints: [LocalEndpoint]
    public var remoteEndpoints: [RemoteEndpoint]
    public var transportProperties: TransportProperties
    public var securityParameters: SecurityParameters

    public init(localEndpoints: [LocalEndpoint] = [],
                remoteEndpoints: [RemoteEndpoint] = [],
                transportProperties: TransportProperties = TransportProperties(),
                securityParameters: SecurityParameters = SecurityParameters()) {
        self.localEndpoints = localEndpoints
        self.remoteEndpoints = remoteEndpoints
        self.transportProperties = transportProperties
        self.securityParameters = securityParameters
    }

    public func resolve() -> (local: [LocalEndpoint], remote: [RemoteEndpoint]) {
        // Placeholder for implementation
        return ([], [])
    }

    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // Placeholder for implementation
    }
}
