//
//  Endpoint.swift
//  
//
//  Maximilian Alexander
//

import Foundation

public protocol Endpoint: Sendable {
    var hostName: String? { get set }
    var port: UInt16? { get set }
    var service: String? { get set }
    var ipAddress: String? { get set }
    var interface: String? { get set }
    var multicastGroup: String? { get set }
    var hopLimit: UInt8? { get set }
    var stunServer: (address: String, port: UInt16, credentials: Data)? { get set }
    var protocolIdentifier: String? { get set }
}

public struct LocalEndpoint: Endpoint, Sendable {
    public var hostName: String?
    public var port: UInt16?
    public var service: String?
    public var ipAddress: String?
    public var interface: String?
    public var multicastGroup: String?
    public var hopLimit: UInt8?
    public var stunServer: (address: String, port: UInt16, credentials: Data)?
    public var protocolIdentifier: String?
    
    public init() {}
}

public struct RemoteEndpoint: Endpoint, Sendable {
    public var hostName: String?
    public var port: UInt16?
    public var service: String?
    public var ipAddress: String?
    public var interface: String?
    public var multicastGroup: String?
    public var hopLimit: UInt8?
    public var stunServer: (address: String, port: UInt16, credentials: Data)?
    public var protocolIdentifier: String?

    public init() {}
}
