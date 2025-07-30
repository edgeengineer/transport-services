//
//  LinuxPlatform.swift
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

#if os(Linux)

/// Linux platform implementation using io_uring
public final class LinuxPlatform: Platform {
    
    public init() {}
    
    public func createConnection(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformConnection {
        fatalError("Linux platform not yet implemented - will use io_uring")
    }
    
    public func createListener(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformListener {
        fatalError("Linux platform not yet implemented - will use io_uring")
    }
    
    public func gatherCandidates(preconnection: Preconnection) async throws -> CandidateSet {
        fatalError("Linux platform not yet implemented - will use io_uring")
    }
    
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        // Linux with io_uring supports TCP and UDP
        for layer in stack.layers {
            switch layer {
            case .tcp, .udp:
                continue
            case .tls:
                // Would need OpenSSL or similar
                continue
            default:
                return false
            }
        }
        return true
    }
    
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        fatalError("Linux platform not yet implemented - will use netlink")
    }
}

#endif
