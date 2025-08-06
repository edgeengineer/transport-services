//
//  Listener.swift
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

/// Represents a passive endpoint that listens for incoming connections
/// Based on RFC 9622 Section 7.2
public protocol Listener: Sendable {
    /// The preconnection used to create this listener
    var preconnection: Preconnection { get }
    
    /// Event handler for transport events
    var eventHandler: @Sendable (TransportServicesEvent) -> Void { get }
    
    /// Stop listening for incoming connections
    func stop() async
    
    /// Set the maximum number of new connections to accept
    func setNewConnectionLimit(_ value: UInt?) async
    
    /// The current connection limit
    var newConnectionLimit: UInt? { get async }

    /// The number of accepted connections
    var acceptedConnectionCount: UInt { get async }

    /// Listener properties
    var properties: TransportProperties { get async }
}

/// Extension for multicast support
public extension Listener {
    /// Join a multicast group (for multicast listeners)
    func joinMulticastGroup(_ group: String, interface: String? = nil) async throws {
        // Default implementation throws not supported
        throw TransportServicesError.notSupported(reason: "Multicast not supported by this listener")
    }
    
    /// Leave a multicast group
    func leaveMulticastGroup(_ group: String, interface: String? = nil) async throws {
        // Default implementation throws not supported
        throw TransportServicesError.notSupported(reason: "Multicast not supported by this listener")
    }
}
