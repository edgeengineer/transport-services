//
//  Listener.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

/// Represents a passive endpoint that listens for incoming connections
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public actor Listener {
    public let preconnection: Preconnection
    public nonisolated let eventHandler: @Sendable (TransportServicesEvent) -> Void
    private let platformListener: any PlatformListener
    private let platform: Platform
    private var isListening: Bool = false
    private var acceptTask: Task<Void, Never>?
    private var newConnectionLimit: UInt?
    private var acceptedConnections: UInt = 0
    
    /// Initialize a new listener
    init(preconnection: Preconnection,
         eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void,
         platformListener: any PlatformListener,
         platform: Platform) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self.platformListener = platformListener
        self.platform = platform
    }
    
    /// Stop listening for incoming connections
    public func stop() async {
        guard isListening else { return }
        
        isListening = false
        acceptTask?.cancel()
        await platformListener.stop()
        eventHandler(.stopped(self))
    }
    
    /// Set the maximum number of new connections to accept
    public func setNewConnectionLimit(_ value: UInt?) {
        self.newConnectionLimit = value
    }
    
    /// Get the current connection limit
    public func getNewConnectionLimit() -> UInt? {
        return newConnectionLimit
    }
    
    /// Get the number of accepted connections
    public func getAcceptedConnectionCount() -> UInt {
        return acceptedConnections
    }
    
    /// Accept incoming connections in a loop
    func acceptLoop() async {
        isListening = true
        
        acceptTask = Task {
            while isListening && !Task.isCancelled {
                // Check connection limit
                if let limit = newConnectionLimit, acceptedConnections >= limit {
                    // Stop accepting new connections
                    break
                }
                
                do {
                    // Accept a new connection
                    let platformConnection = try await platformListener.accept()
                    acceptedConnections += 1
                    
                    // Create TAPS connection wrapper
                    let connection = Connection(
                        preconnection: preconnection,
                        eventHandler: eventHandler,
                        platformConnection: platformConnection,
                        platform: platform
                    )
                    
                    // Deliver connection to application
                    eventHandler(.connectionReceived(self, connection))
                    
                    // Start receiving on the connection if bidirectional
                    if preconnection.transportProperties.direction != .unidirectionalSend {
                        Task {
                            await connection.startReceiving()
                        }
                    }
                    
                } catch {
                    // If we get an error, it might mean the listener was stopped
                    // or there was a network error
                    if isListening {
                        // Log error but continue listening
                        print("Error accepting connection: \(error)")
                    }
                }
            }
            
            // If we exited the loop due to connection limit, keep the listener active
            // but stop accepting new connections
            if let limit = newConnectionLimit, acceptedConnections >= limit {
                print("Connection limit reached: \(limit)")
            }
        }
        
        await acceptTask?.value
    }
    
    /// Get listener properties
    public func getProperties() -> TransportProperties {
        return preconnection.transportProperties
    }
}

/// Extension for multicast support
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Listener {
    /// Join a multicast group (for multicast listeners)
    public func joinMulticastGroup(_ group: String, interface: String? = nil) async throws {
        // Platform-specific implementation would handle multicast join
        guard let multicastGroup = preconnection.localEndpoints.first?.multicastGroup else {
            throw TransportServicesError.invalidConfiguration
        }
        
        // Validate this is a multicast endpoint
        if !isMulticastAddress(multicastGroup) {
            throw TransportServicesError.invalidConfiguration
        }
        
        // Platform would handle the actual multicast join
    }
    
    /// Leave a multicast group
    public func leaveMulticastGroup(_ group: String, interface: String? = nil) async throws {
        // Platform-specific implementation would handle multicast leave
    }
    
    private func isMulticastAddress(_ address: String) -> Bool {
        // Check if address is in multicast range
        // IPv4: 224.0.0.0 - 239.255.255.255
        // IPv6: ff00::/8
        if address.contains(":") {
            // IPv6
            return address.lowercased().hasPrefix("ff")
        } else {
            // IPv4
            let parts = address.split(separator: ".")
            if parts.count == 4, let firstOctet = Int(parts[0]) {
                return firstOctet >= 224 && firstOctet <= 239
            }
        }
        return false
    }
}
