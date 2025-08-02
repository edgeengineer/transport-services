//
//  ApplePreconnection.swift
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

/// Apple platform-specific implementation of Preconnection
public struct ApplePreconnection: Preconnection {
    public var localEndpoints: [LocalEndpoint]
    public var remoteEndpoints: [RemoteEndpoint]
    public var transportProperties: TransportProperties
    public var securityParameters: SecurityParameters
    
    // Private platform instance
    private let platform: Platform
    
    public init(localEndpoints: [LocalEndpoint] = [],
                remoteEndpoints: [RemoteEndpoint] = [],
                transportProperties: TransportProperties = TransportProperties(),
                securityParameters: SecurityParameters = SecurityParameters()) {
        self.localEndpoints = localEndpoints
        self.remoteEndpoints = remoteEndpoints
        self.transportProperties = transportProperties
        self.securityParameters = securityParameters
        self.platform = ApplePlatform()
    }
    
    // MARK: - Preconnection Protocol Implementation
    
    public func resolve() async -> (local: [LocalEndpoint], remote: [RemoteEndpoint]) {
        // Use the platform's candidate gathering capability
        do {
            let candidateSet = try await platform.gatherCandidates(preconnection: self)
            
            // Convert platform candidates back to LocalEndpoint and RemoteEndpoint
            var resolvedLocal: [LocalEndpoint] = []
            var resolvedRemote: [RemoteEndpoint] = []
            
            // Process local candidates
            for candidate in candidateSet.localCandidates {
                // Each local candidate represents a resolved local endpoint
                // with potentially multiple addresses
                resolvedLocal.append(candidate.endpoint)
            }
            
            // Process remote candidates  
            for candidate in candidateSet.remoteCandidates {
                // Each remote candidate represents a resolved remote endpoint
                // with potentially multiple addresses
                resolvedRemote.append(candidate.endpoint)
            }
            
            return (resolvedLocal, resolvedRemote)
        } catch {
            // If candidate gathering fails, return the original endpoints
            // This allows the application to proceed with unresolved endpoints
            return (localEndpoints, remoteEndpoints)
        }
    }
    
    public func initiate(timeout: TimeInterval?, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Connection {
        // Gather candidates
        let _ = try await platform.gatherCandidates(preconnection: self)
        
        // Create platform connection
        let handler: @Sendable (TransportServicesEvent) -> Void = eventHandler ?? { _ in }
        let connection = platform.createConnection(
            preconnection: self,
            eventHandler: handler
        )
        
        // Initiate the connection - platform specific implementation will handle state updates and events
        if let appleConnection = connection as? AppleConnection {
            await appleConnection.initiate()
        }
        
        return connection
    }
    
    public func initiateWithSend(messageData: Data, messageContext: MessageContext, timeout: TimeInterval?, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Connection {
        // Ensure message is safely replayable for 0-RTT
        guard messageContext.safelyReplayable else {
            throw TransportServicesError.messageNotSafelyReplayable
        }
        
        let connection = try await initiate(
            timeout: timeout,
            eventHandler: eventHandler
        )
        
        // Send initial data
        try await connection.send(data: messageData, context: messageContext)
        
        return connection
    }
    
    public func listen(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Listener {
        // Validate that local endpoint is specified
        guard !localEndpoints.isEmpty else {
            throw TransportServicesError.noLocalEndpoint
        }
        
        // Create platform listener
        let handler: @Sendable (TransportServicesEvent) -> Void = eventHandler ?? { _ in }
        let listener = try AppleListener(
            preconnection: self,
            eventHandler: handler
        )
        
        // Start listening
        try await listener.listen()
        
        return listener
    }
    
    public func rendezvous(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> (any Connection, any Listener) {
        // Validate endpoints
        guard !localEndpoints.isEmpty else {
            throw TransportServicesError.noLocalEndpoint
        }
        guard !remoteEndpoints.isEmpty else {
            throw TransportServicesError.noRemoteEndpoint
        }
        
        // Start both outbound and inbound simultaneously
        let handler: @Sendable (TransportServicesEvent) -> Void = eventHandler ?? { _ in }
        async let outbound = initiate(timeout: nil, eventHandler: handler)
        async let inbound = listen(eventHandler: handler)
        
        let connection = try await outbound
        let listener = try await inbound
        
        // Send RendezvousDone event
        handler(TransportServicesEvent.rendezvousDone(self, connection))
        
        return (connection, listener)
    }
    
    public mutating func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        self.remoteEndpoints.append(contentsOf: remoteEndpoints)
    }
}

// MARK: - Helper Functions

private func withTimeout<T>(_ timeout: TimeInterval?, operation: @escaping @Sendable () async throws -> T) async throws -> T where T: Sendable {
    if let timeout = timeout {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @Sendable in
                try await operation()
            }
            
            group.addTask { @Sendable in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TransportServicesError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    } else {
        return try await operation()
    }
}