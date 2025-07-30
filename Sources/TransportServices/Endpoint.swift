//
//  Endpoint.swift
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

public enum BLEIdentifier: Sendable, Hashable {
    case uuid(UUID)
    case address(String)
}

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

    // BLE Properties
    var bleIdentifier: BLEIdentifier? { get set }
    var psm: UInt16? { get set }
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

    // BLE Properties
    public var bleIdentifier: BLEIdentifier?
    public var psm: UInt16?
    
    public init() {}
    
    // Convenience initializers
    public static func tcp(port: UInt16, interface: String? = nil) -> LocalEndpoint {
        var endpoint = LocalEndpoint()
        endpoint.port = port
        endpoint.interface = interface
        return endpoint
    }
    
    public static func udp(port: UInt16, interface: String? = nil) -> LocalEndpoint {
        var endpoint = LocalEndpoint()
        endpoint.port = port
        endpoint.interface = interface
        return endpoint
    }
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

    // BLE Properties
    public var bleIdentifier: BLEIdentifier?
    public var psm: UInt16?

    public init() {}
    
    // Convenience initializers
    public static func tcp(host: String, port: UInt16) -> RemoteEndpoint {
        var endpoint = RemoteEndpoint()
        endpoint.hostName = host
        endpoint.port = port
        return endpoint
    }
    
    public static func udp(host: String, port: UInt16) -> RemoteEndpoint {
        var endpoint = RemoteEndpoint()
        endpoint.hostName = host
        endpoint.port = port
        return endpoint
    }
    
    public static func tcp(ip: String, port: UInt16) -> RemoteEndpoint {
        var endpoint = RemoteEndpoint()
        endpoint.ipAddress = ip
        endpoint.port = port
        return endpoint
    }
}
