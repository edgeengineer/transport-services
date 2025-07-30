//
//  AppleListener.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation
#if canImport(Network)
import Network

/// Apple platform listener implementation
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
actor AppleListener: @preconcurrency PlatformListener {
    private let preconnection: Preconnection
    private let eventHandler: @Sendable (TransportServicesEvent) -> Void
    private var nwListener: NWListener?
    private let queue = DispatchQueue(label: "apple.listener")
    
    // Accept queue for incoming connections
    private var pendingConnections: [any PlatformConnection] = []
    private var acceptContinuation: CheckedContinuation<any PlatformConnection, Error>?
    
    init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        
        // Initialize with empty state
    }
    
    func listen() async throws {
        // Create NWParameters based on preconnection properties
        let params = createNWParameters()
        
        // Get local endpoint
        guard let localEndpoint = preconnection.localEndpoints.first else {
            throw TransportError.noLocalEndpoint
        }
        
        // Create NWListener
        let listener: NWListener
        if let port = localEndpoint.port {
            let nwPort = NWEndpoint.Port(integerLiteral: port)
            listener = try NWListener(using: params, on: nwPort)
        } else {
            // Let the system choose a port
            listener = try NWListener(using: params)
        }
        
        self.nwListener = listener
        
        // Set up new connection handler
        listener.newConnectionHandler = { [weak self] nwConnection in
            Task { [weak self] in
                await self?.handleNewConnection(nwConnection)
            }
        }
        
        // Start listening
        listener.start(queue: queue)
    }
    
    func accept() async throws -> any PlatformConnection {
        // If we have pending connections, return one immediately
        if !pendingConnections.isEmpty {
            return pendingConnections.removeFirst()
        }
        
        // Otherwise wait for a new connection
        return try await withCheckedThrowingContinuation { continuation in
            self.acceptContinuation = continuation
        }
    }
    
    func stop() async {
        nwListener?.cancel()
        nwListener = nil
        
        // Resume any waiting accept with an error
        if let continuation = acceptContinuation {
            continuation.resume(throwing: TransportError.listenerStopped)
            acceptContinuation = nil
        }
        
        // Clear pending connections
        pendingConnections.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func handleNewConnection(_ nwConnection: NWConnection) {
        // Create a new AppleConnection wrapper with the accepted connection
        let connection = AppleConnection(
            preconnection: preconnection,
            eventHandler: eventHandler,
            nwConnection: nwConnection
        )
        
        // Start the connection
        nwConnection.start(queue: queue)
        
        // If someone is waiting for a connection, deliver it immediately
        if let continuation = acceptContinuation {
            continuation.resume(returning: connection)
            acceptContinuation = nil
        } else {
            // Otherwise queue it
            pendingConnections.append(connection)
        }
    }
    
    private func createNWParameters() -> NWParameters {
        let properties = preconnection.transportProperties
        let params: NWParameters
        
        // Select protocol based on transport properties
        if properties.reliability == .require {
            params = NWParameters.tcp
        } else {
            params = NWParameters.udp
        }
        
        // Configure TLS if needed
        if preconnection.securityParameters.allowedSecurityProtocols != nil {
            let tlsOptions = NWProtocolTLS.Options()
            params.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
        }
        
        return params
    }
}

/// Transport errors specific to listener
extension TransportError {
    static let noLocalEndpoint = TransportError.invalidEndpoint
    static let listenerStopped = TransportError.connectionClosed
}

#endif