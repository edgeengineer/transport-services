//
//  WindowsPlatform.swift
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

#if os(Windows)

/// Windows platform implementation using IOCP
public final class WindowsPlatform: Platform {
    
    public init() {}
    
    public func createConnection(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformConnection {
        fatalError("Windows platform not yet implemented - will use IOCP")
    }
    
    public func createListener(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) -> any PlatformListener {
        fatalError("Windows platform not yet implemented - will use IOCP")
    }
    
    public func gatherCandidates(preconnection: Preconnection) async throws -> CandidateSet {
        fatalError("Windows platform not yet implemented - will use IOCP")
    }
    
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        // Windows with IOCP supports TCP and UDP
        for layer in stack.layers {
            switch layer {
            case .tcp, .udp:
                continue
            case .tls:
                // Would use SChannel
                continue
            default:
                return false
            }
        }
        return true
    }
    
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        fatalError("Windows platform not yet implemented - will use Windows API")
    }
}

#endif
