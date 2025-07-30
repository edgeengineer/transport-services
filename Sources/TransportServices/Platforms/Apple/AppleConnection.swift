//
//  AppleConnection.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation
#if canImport(Network)
import Network

/// Apple platform connection implementation
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
actor AppleConnection: @preconcurrency PlatformConnection {
    private let preconnection: Preconnection
    private let eventHandler: @Sendable (TransportServicesEvent) -> Void
    internal var nwConnection: NWConnection?
    private let queue = DispatchQueue(label: "apple.connection")
    private var state: ConnectionState = .establishing
    
    init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void, nwConnection: NWConnection? = nil) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self.nwConnection = nwConnection
    }
    
    private func updateState(_ newState: ConnectionState) {
        self.state = newState
    }
    
    func initiate() async throws {
        // Convert preconnection properties to NWParameters
        let params = createNWParameters()
        
        // Select remote endpoint - for now, use the first one
        guard let remoteEndpoint = preconnection.remoteEndpoints.first else {
            throw TransportError.noRemoteEndpoint
        }
        
        // Create NWEndpoint
        let endpoint = try createNWEndpoint(from: remoteEndpoint)
        
        // Create connection
        let connection = NWConnection(to: endpoint, using: params)
        self.nwConnection = connection
        
        // Set up state handler and wait for connection
        let connectionReady = AsyncStream<Void> { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                Task {
                    switch state {
                    case .ready:
                        await self?.updateState(.established)
                        continuation.yield()
                        continuation.finish()
                        
                    case .failed(_):
                        await self?.updateState(.closed)
                        continuation.finish()
                        
                    default:
                        break
                    }
                }
            }
            
            connection.start(queue: queue)
        }
        
        // Wait for connection to be ready
        for await _ in connectionReady {
            return
        }
        
        // If we get here without being ready, it failed
        if state != .established {
            throw TransportError.establishmentFailed
        }
    }
    
    func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        guard let connection = nwConnection else {
            throw TransportError.notConnected
        }
        
        // Create content context for the message
        let content = NWConnection.ContentContext(
            identifier: "message",
            metadata: []
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: content, isComplete: endOfMessage, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext, Bool) {
        guard let connection = nwConnection else {
            throw TransportError.notConnected
        }
        
        let minLength = minIncompleteLength ?? 1
        let maxLength = maxLength ?? 65536
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: minLength, maximumLength: maxLength) { data, context, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    let messageContext = MessageContext()
                    continuation.resume(returning: (data, messageContext, isComplete))
                } else {
                    continuation.resume(throwing: TransportError.connectionClosed)
                }
            }
        }
    }
    
    func close() async {
        nwConnection?.cancel()
        state = .closed
    }
    
    func abort() async {
        nwConnection?.forceCancel()
        state = .closed
    }
    
    func getState() -> ConnectionState {
        return state
    }
    
    nonisolated func setProperty(_ property: ConnectionProperty, value: Any) async throws {
        // Implement property setting based on NWConnection capabilities
    }
    
    nonisolated func getProperty(_ property: ConnectionProperty) async -> Any? {
        // Implement property getting based on NWConnection capabilities
        return nil
    }
    
    // MARK: - Private Methods
    
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
            params.defaultProtocolStack.applicationProtocols.insert(NWProtocolTLS.Options(), at: 0)
        }
        
        // Configure other properties
        if properties.multipath != .disabled {
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
                params.multipathServiceType = properties.multipathPolicy == .handover ? .handover : .interactive
            }
        }
        
        return params
    }
    
    private func createNWEndpoint(from endpoint: RemoteEndpoint) throws -> NWEndpoint {
        if let ipAddress = endpoint.ipAddress, let port = endpoint.port {
            let host = NWEndpoint.Host(ipAddress)
            let port = NWEndpoint.Port(integerLiteral: port)
            return NWEndpoint.hostPort(host: host, port: port)
        } else if let hostName = endpoint.hostName, let port = endpoint.port {
            let host = NWEndpoint.Host(hostName)
            let port = NWEndpoint.Port(integerLiteral: port)
            return NWEndpoint.hostPort(host: host, port: port)
        } else {
            throw TransportError.invalidEndpoint
        }
    }
}

/// Transport errors
enum TransportError: Error {
    case noRemoteEndpoint
    case notConnected
    case connectionClosed
    case establishmentFailed
    case invalidEndpoint
    case invalidInterface
}

#endif