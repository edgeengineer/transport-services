//
//  Connection.swift
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

/// Represents an established or establishing transport connection
public actor Connection {
    public let preconnection: Preconnection
    public nonisolated let eventHandler: @Sendable (TransportServicesEvent) -> Void
    private let platformConnection: any PlatformConnection
    private let platform: Platform
    public private(set) var state: ConnectionState = .establishing
    private var connectionGroup: ConnectionGroup?
    private var _properties: TransportProperties
    
    /// Initialize a new connection
    init(preconnection: Preconnection, 
         eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void,
         platformConnection: any PlatformConnection,
         platform: Platform) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self.platformConnection = platformConnection
        self.platform = platform
        self._properties = preconnection.transportProperties
    }
    
    /// Update connection state (internal use)
    func updateState(_ newState: ConnectionState) {
        self.state = newState
    }
    
    /// Check if the connection is established
    public var isEstablished: Bool {
        state == .established
    }
    
    /// Check if the connection is closed
    public var isClosed: Bool {
        state == .closed
    }
    
    // MARK: - Connection Lifecycle
    
    /// Close the connection gracefully
    public func close() async {
        state = .closing
        await platformConnection.close()
        state = .closed
        eventHandler(.closed(self))
    }
    
    /// Abort the connection immediately
    public func abort() {
        state = .closing
        platformConnection.abort()
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
            await newConnection.setGroup(group)
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
        guard isEstablished else {
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
        guard isEstablished else {
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
    public func startReceiving(minIncompleteLength: Int? = nil, maxLength: Int? = nil) {
        Task {
            while isEstablished {
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
    
    /// Transport properties for this connection
    public var properties: TransportProperties {
        get { _properties }
        set {
            _properties = newValue
            // Note: Setting bulk properties would require recreating the connection
            // as most transport properties can't be changed after establishment
        }
    }
    
    /// Set a specific connection property
    public func setConnectionProperty(_ property: ConnectionProperty) async throws {
        try await platformConnection.setProperty(property, value: property)
        
        // Update local properties based on the property type
        switch property {
        case .multipathPolicy(let policy):
            _properties.multipathPolicy = policy
        case .priority(let priority):
            _properties.connPriority = UInt(priority)
        case .connectionTimeout(let timeout):
            _properties.connTimeout = timeout
        case .keepAlive(let enabled, let interval):
            _properties.keepAlive = enabled ? .require : .prohibit
            _properties.keepAliveTimeout = interval
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
    
    /// The connection group this connection belongs to
    public var group: ConnectionGroup? {
        connectionGroup
    }
    
    /// Set the connection group
    public func setGroup(_ group: ConnectionGroup?) {
        connectionGroup = group
    }
}

/// Represents a group of related connections
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
    
    /// The number of connections in the group
    public var connectionCount: Int {
        connections.count
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
public protocol ConnectionGroupScheduler: AnyObject {
    func schedule(data: Data, context: MessageContext, group: ConnectionGroup) async -> Connection?
}
