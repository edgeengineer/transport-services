//
//  TransportServices.swift
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

/// Global convenience functions for creating Transport Services objects

/// Create a new Preconnection with the appropriate platform implementation
public func NewPreconnection(localEndpoints: [LocalEndpoint] = [],
                           remoteEndpoints: [RemoteEndpoint] = [],
                           transportProperties: TransportProperties = TransportProperties(),
                           securityParameters: SecurityParameters = SecurityParameters()) -> any Preconnection {
    #if canImport(Network)
    return ApplePreconnection(
        localEndpoints: localEndpoints,
        remoteEndpoints: remoteEndpoints,
        transportProperties: transportProperties,
        securityParameters: securityParameters
    )
    #elseif os(Linux)
    // TODO: Return LinuxPreconnection when implemented
    fatalError("Linux platform not yet implemented")
    #elseif os(Windows)
    // TODO: Return WindowsPreconnection when implemented
    fatalError("Windows platform not yet implemented")
    #else
    fatalError("Unsupported platform")
    #endif
}