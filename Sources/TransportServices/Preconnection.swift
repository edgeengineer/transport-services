//
//  Preconnection.swift
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

public struct Preconnection: Sendable {
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
        
        // Initialize platform based on current OS
        #if canImport(Network)
        self.platform = ApplePlatform()
        #elseif os(Linux)
        self.platform = LinuxPlatform()
        #elseif os(Windows)
        self.platform = WindowsPlatform()
        #else
        fatalError("Unsupported platform")
        #endif
    }
    
    // Init with custom platform for testing
    public init(localEndpoints: [LocalEndpoint] = [],
                remoteEndpoints: [RemoteEndpoint] = [],
                transportProperties: TransportProperties = TransportProperties(),
                securityParameters: SecurityParameters = SecurityParameters(),
                platform: Platform) {
        self.localEndpoints = localEndpoints
        self.remoteEndpoints = remoteEndpoints
        self.transportProperties = transportProperties
        self.securityParameters = securityParameters
        self.platform = platform
    }

    public func resolve() -> (local: [LocalEndpoint], remote: [RemoteEndpoint]) {
        // Placeholder for implementation
        return ([], [])
    }
    
    // MARK: - Connection Methods
    
    /// Initiate a connection to a remote endpoint
    public func initiate(
        timeout: TimeInterval? = nil,
        eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil
    ) async throws -> Connection {
        // Gather candidates
        let _ = try await platform.gatherCandidates(preconnection: self)
        
        // Create platform connection
        let handler: @Sendable (TransportServicesEvent) -> Void = eventHandler ?? { _ in }
        let platformConnection = platform.createConnection(
            preconnection: self,
            eventHandler: handler
        )
        
        // Create TAPS connection wrapper
        let connection = Connection(
            preconnection: self,
            eventHandler: handler,
            platformConnection: platformConnection,
            platform: platform
        )
        
        // Initiate the platform connection
        try await withTimeout(timeout) {
            try await platformConnection.initiate()
        }
        
        // Update connection state
        await connection.updateState(ConnectionState.established)
        
        // Send Ready event
        handler(TransportServicesEvent.ready(connection))
        
        return connection
    }
    
    /// Initiate a connection with initial data
    public func initiateWithSend(
        messageData: Data,
        messageContext: MessageContext = MessageContext(),
        timeout: TimeInterval? = nil,
        eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil
    ) async throws -> Connection {
        // Ensure message is safely replayable for 0-RTT
        guard messageContext.safelyReplayable else {
            throw TransportServicesError.messageNotSafelyReplayable
        }
        
        let connection: Connection = try await initiate(
            timeout: timeout,
            eventHandler: eventHandler
        )
        
        // Send initial data
        try await connection.send(data: messageData, context: messageContext)
        
        return connection
    }
    
    /// Listen for incoming connections
    public func listen(
        eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil
    ) async throws -> Listener {
        // Validate that local endpoint is specified
        guard !localEndpoints.isEmpty else {
            throw TransportServicesError.noLocalEndpoint
        }
        
        // Create platform listener
        let handler: @Sendable (TransportServicesEvent) -> Void = eventHandler ?? { _ in }
        let platformListener = platform.createListener(
            preconnection: self,
            eventHandler: handler
        )
        
        // Create TAPS listener wrapper
        let listener = Listener(
            preconnection: self,
            eventHandler: handler,
            platformListener: platformListener,
            platform: platform
        )
        
        // Start listening
        try await platformListener.listen()
        
        // Start accepting connections in the background
        Task {
            await listener.acceptLoop()
        }
        
        return listener
    }
    
    /// Establish a peer-to-peer connection using rendezvous
    public func rendezvous(
        eventHandler: ((@Sendable (TransportServicesEvent) -> Void))? = nil
    ) async throws -> (Connection, Listener) {
        // Validate endpoints
        guard !localEndpoints.isEmpty else {
            throw TransportServicesError.noLocalEndpoint
        }
        guard !remoteEndpoints.isEmpty else {
            throw TransportServicesError.noRemoteEndpoint
        }
        
        // Start both outbound and inbound simultaneously
        let handler: @Sendable (TransportServicesEvent) -> Void = eventHandler ?? { _ in }
        async let outbound = initiate(eventHandler: handler)
        async let inbound = listen(eventHandler: handler)
        
        let connection = try await outbound
        let listener = try await inbound
        
        // Send RendezvousDone event
        handler(TransportServicesEvent.rendezvousDone(self, connection))
        
        return (connection, listener)
    }

    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // Placeholder for implementation
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
