//
//  Connection.swift
//  
//
//  Maximilian Alexander
//

import Foundation

/// Represents an established or establishing transport connection
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public actor Connection {
    public let preconnection: Preconnection
    public nonisolated let eventHandler: @Sendable (TransportServicesEvent) -> Void
    private let platformConnection: any PlatformConnection
    private let platform: Platform
    private var state: ConnectionState = .establishing
    private var connectionGroup: ConnectionGroup?
    private var properties: TransportProperties
    
    /// Initialize a new connection
    init(preconnection: Preconnection, 
         eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void,
         platformConnection: any PlatformConnection,
         platform: Platform) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self.platformConnection = platformConnection
        self.platform = platform
        self.properties = preconnection.transportProperties
    }
    
    // MARK: - Connection Lifecycle
    
    /// Get the current connection state
    public func getState() -> ConnectionState {
        return platformConnection.getState()
    }
    
    /// Close the connection gracefully
    public func close() async {
        state = .closing
        await platformConnection.close()
        state = .closed
        eventHandler(.closed(self))
    }
    
    /// Abort the connection immediately
    public func abort() async {
        state = .closing
        await platformConnection.abort()
        state = .closed
        eventHandler(.connectionError(self, reason: "Connection aborted"))
    }
    
    /// Clone this connection to create a new connection with same properties
    public func clone() async throws -> Connection {
        // Create new platform connection with same preconnection
        let newPlatformConnection = platform.createConnection(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        let newConnection = Connection(
            preconnection: preconnection,
            eventHandler: eventHandler,
            platformConnection: newPlatformConnection,
            platform: platform
        )
        
        // Copy connection group membership
        if let group = connectionGroup {
            await group.addConnection(newConnection)
            await newConnection.setConnectionGroup(group)
        }
        
        // Initiate the cloned connection
        do {
            try await newPlatformConnection.initiate()
            eventHandler(.ready(newConnection))
        } catch {
            eventHandler(.cloneError(self, reason: error.localizedDescription))
            throw error
        }
        
        return newConnection
    }
    
    // MARK: - Data Transfer
    
    /// Send data over the connection
    public func send(data: Data, context: MessageContext = MessageContext(), endOfMessage: Bool = true) async throws {
        guard state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        do {
            try await platformConnection.send(data: data, context: context, endOfMessage: endOfMessage)
            eventHandler(.sent(self, context))
        } catch {
            eventHandler(.sendError(self, context, reason: error.localizedDescription))
            throw error
        }
    }
    
    /// Receive data from the connection
    public func receive(minIncompleteLength: Int? = nil, maxLength: Int? = nil) async throws -> (Data, MessageContext) {
        guard state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        do {
            let (data, context, endOfMessage) = try await platformConnection.receive(
                minIncompleteLength: minIncompleteLength,
                maxLength: maxLength
            )
            
            if endOfMessage {
                eventHandler(.received(self, data, context))
            } else {
                eventHandler(.receivedPartial(self, data, context, endOfMessage: false))
            }
            
            return (data, context)
        } catch {
            let context = MessageContext()
            eventHandler(.receiveError(self, context, reason: error.localizedDescription))
            throw error
        }
    }
    
    /// Start receiving data continuously
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func startReceiving(minIncompleteLength: Int? = nil, maxLength: Int? = nil) {
        Task {
            while state == .established {
                do {
                    let _ = try await receive(
                        minIncompleteLength: minIncompleteLength,
                        maxLength: maxLength
                    )
                } catch {
                    // Connection closed or error occurred
                    break
                }
            }
        }
    }
    
    // MARK: - Properties
    
    /// Get current transport properties
    public func getProperties() -> TransportProperties {
        return properties
    }
    
    /// Set a connection property
    public func setConnectionProperty(_ property: ConnectionProperty) async throws {
        try await platformConnection.setProperty(property, value: property)
        
        // Update local properties based on the property type
        switch property {
        case .multipathPolicy(let policy):
            properties.multipathPolicy = policy
        case .priority(let priority):
            properties.connPriority = UInt(priority)
        case .connectionTimeout(let timeout):
            properties.connTimeout = timeout
        case .keepAlive(let enabled, let interval):
            properties.keepAlive = enabled ? .require : .prohibit
            properties.keepAliveTimeout = interval
        default:
            break
        }
    }
    
    /// Get a connection property
    public func getConnectionProperty(_ property: ConnectionProperty) async -> Any? {
        return await platformConnection.getProperty(property)
    }
    
    // MARK: - Endpoint Management
    
    /// Add remote endpoints for multipath or migration
    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) async {
        // This would be implemented by the platform to add new paths
        // For now, just update the preconnection copy
        var updatedPreconnection = preconnection
        updatedPreconnection.remoteEndpoints.append(contentsOf: remoteEndpoints)
    }
    
    /// Remove remote endpoints
    public func removeRemote(_ remoteEndpoints: [RemoteEndpoint]) async {
        // This would be implemented by the platform to remove paths
        var updatedPreconnection = preconnection
        updatedPreconnection.remoteEndpoints.removeAll { endpoint in
            remoteEndpoints.contains { $0.hostName == endpoint.hostName && $0.port == endpoint.port }
        }
    }
    
    /// Add local endpoints for multipath or migration
    public func addLocal(_ localEndpoints: [LocalEndpoint]) async {
        // This would be implemented by the platform to add new local paths
        var updatedPreconnection = preconnection
        updatedPreconnection.localEndpoints.append(contentsOf: localEndpoints)
    }
    
    /// Remove local endpoints
    public func removeLocal(_ localEndpoints: [LocalEndpoint]) async {
        // This would be implemented by the platform to remove local paths
        var updatedPreconnection = preconnection
        updatedPreconnection.localEndpoints.removeAll { endpoint in
            localEndpoints.contains { $0.interface == endpoint.interface && $0.port == endpoint.port }
        }
    }
    
    // MARK: - Connection Groups
    
    /// Set the connection group for this connection
    func setConnectionGroup(_ group: ConnectionGroup) async {
        self.connectionGroup = group
    }
    
    /// Get the connection group for this connection
    public func getConnectionGroup() -> ConnectionGroup? {
        return connectionGroup
    }
}

/// Represents a group of related connections
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public actor ConnectionGroup {
    private var connections: Set<ObjectIdentifier> = []
    private weak var scheduler: ConnectionGroupScheduler?
    
    public init(scheduler: ConnectionGroupScheduler? = nil) {
        self.scheduler = scheduler
    }
    
    /// Add a connection to the group
    func addConnection(_ connection: Connection) {
        connections.insert(ObjectIdentifier(connection))
    }
    
    /// Remove a connection from the group
    func removeConnection(_ connection: Connection) {
        connections.remove(ObjectIdentifier(connection))
    }
    
    /// Get the number of connections in the group
    public func connectionCount() -> Int {
        return connections.count
    }
    
    /// Close all connections in the group
    public func closeGroup() async {
        // Implementation would close all connections
    }
    
    /// Abort all connections in the group
    public func abortGroup() async {
        // Implementation would abort all connections
    }
}

/// Connection group scheduler for managing multiple connections
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol ConnectionGroupScheduler: AnyObject {
    func schedule(data: Data, context: MessageContext, group: ConnectionGroup) async -> Connection?
}
