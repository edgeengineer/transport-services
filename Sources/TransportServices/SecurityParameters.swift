//
//  SecurityParameters.swift
//  
//
//  Maximilian Alexander
//

import Foundation

public struct SecurityParameters: Sendable {
    public enum SecurityProtocol: Sendable {
        case tls_1_2
        case tls_1_3
    }

    public var allowedSecurityProtocols: [SecurityProtocol]?
    public var serverCertificate: [Data]?
    public var clientCertificate: [Data]?
    public var pinnedServerCertificate: [Data]?
    public var alpn: [String]?
    public var supportedGroup: [String]?
    public var ciphersuite: [String]?
    public var signatureAlgorithm: [String]?
    public var maxCachedSessions: Int?
    public var cachedSessionLifetimeSeconds: Int?
    public var preSharedKey: (key: Data, identity: Data)?
    
    public typealias TrustVerificationCallback = @Sendable () -> Bool
    public typealias IdentityChallengeCallback = @Sendable () -> Void

    public var trustVerificationCallback: TrustVerificationCallback?
    public var identityChallengeCallback: IdentityChallengeCallback?

    public init() {}

    public static func disabled() -> SecurityParameters {
        // Return a configuration that disables security
        return SecurityParameters()
    }

    public static func opportunistic() -> SecurityParameters {
        // Return a configuration for opportunistic security
        return SecurityParameters()
    }
}
