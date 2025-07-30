//
//  Taps.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

/// Transport Services API main entry point
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public actor TransportServices {
    private let platform: Platform
    
    /// Initialize Transport Services with platform-specific implementation
    public init() {
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
    
    /// Initialize Transport Services with a custom platform implementation
    public init(platform: Platform) {
        self.platform = platform
    }
    
    /// Create a new Preconnection with specified endpoints and properties
    public func newPreconnection(
        localEndpoints: [LocalEndpoint] = [],
        remoteEndpoints: [RemoteEndpoint] = [],
        transportProperties: TransportProperties = TransportProperties(),
        securityParameters: SecurityParameters = SecurityParameters()
    ) -> Preconnection {
        return Preconnection(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            transportProperties: transportProperties,
            securityParameters: securityParameters
        )
    }
    
    /// Initiate a connection to a remote endpoint
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func initiate(
        preconnection: Preconnection,
        timeout: TimeInterval? = nil,
        eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void
    ) async throws -> Connection {
        // Gather candidates
        let _ = try await platform.gatherCandidates(preconnection: preconnection)
        
        // Create platform connection
        let platformConnection = platform.createConnection(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        // Create TAPS connection wrapper
        let connection = Connection(
            preconnection: preconnection,
            eventHandler: eventHandler,
            platformConnection: platformConnection,
            platform: platform
        )
        
        // Initiate the platform connection
        try await withTimeout(timeout) {
            try await platformConnection.initiate()
        }
        
        // Send Ready event
        eventHandler(.ready(connection))
        
        return connection
    }
    
    /// Initiate a connection with initial data
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func initiateWithSend(
        preconnection: Preconnection,
        messageData: Data,
        messageContext: MessageContext = MessageContext(),
        timeout: TimeInterval? = nil,
        eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void
    ) async throws -> Connection {
        // Ensure message is safely replayable for 0-RTT
        guard messageContext.safelyReplayable else {
            throw TransportServicesError.messageNotSafelyReplayable
        }
        
        let connection = try await initiate(
            preconnection: preconnection,
            timeout: timeout,
            eventHandler: eventHandler
        )
        
        // Send initial data
        try await connection.send(data: messageData, context: messageContext)
        
        return connection
    }
    
    /// Listen for incoming connections
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func listen(
        preconnection: Preconnection,
        eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void
    ) async throws -> Listener {
        // Validate that local endpoint is specified
        guard !preconnection.localEndpoints.isEmpty else {
            throw TransportServicesError.noLocalEndpoint
        }
        
        // Create platform listener
        let platformListener = platform.createListener(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        // Create TAPS listener wrapper
        let listener = Listener(
            preconnection: preconnection,
            eventHandler: eventHandler,
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
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func rendezvous(
        preconnection: Preconnection,
        eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void
    ) async throws -> (Connection, Listener) {
        // Validate endpoints
        guard !preconnection.localEndpoints.isEmpty else {
            throw TransportServicesError.noLocalEndpoint
        }
        guard !preconnection.remoteEndpoints.isEmpty else {
            throw TransportServicesError.noRemoteEndpoint
        }
        
        // Start both outbound and inbound simultaneously
        async let outbound = initiate(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        async let inbound = listen(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        let connection = try await outbound
        let listener = try await inbound
        
        // Send RendezvousDone event
        eventHandler(.rendezvousDone(preconnection, connection))
        
        return (connection, listener)
    }
    
    /// Get available network interfaces
    public func getAvailableInterfaces() async throws -> [NetworkInterface] {
        return try await platform.getAvailableInterfaces()
    }
    
    /// Check if a protocol stack is supported
    public func isProtocolStackSupported(_ stack: ProtocolStack) -> Bool {
        return platform.isProtocolStackSupported(stack)
    }
}

// MARK: - Helper Functions

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
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

/// Transport Services API errors
public enum TransportServicesError: Error {
    case noLocalEndpoint
    case noRemoteEndpoint
    case messageNotSafelyReplayable
    case timeout
    case protocolNotSupported
    case establishmentFailed(reason: String)
    case connectionClosed
    case invalidConfiguration
}
