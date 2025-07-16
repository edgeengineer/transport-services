#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Manages a group of related connections that share properties.
///
/// Connection groups implement the concept from RFC 9622 §7.4 where multiple
/// connections can be logically grouped together, typically for multistreaming
/// protocols like QUIC, SCTP, or HTTP/2.
actor ConnectionGroup {
    
    // MARK: - Properties
    
    /// Unique identifier for this group
    let id: UUID = UUID()
    
    /// All connections in this group
    private var connections: [UUID: Connection] = [:]
    
    /// Shared transport properties for the group
    private var sharedProperties: TransportProperties
    
    /// Security parameters for the group
    private let securityParameters: SecurityParameters
    
    /// Shared framers
    private let framers: [any MessageFramer]
    
    /// Connection scheduler for the group
    private var scheduler: ConnectionScheduler = .default
    
    // MARK: - Types
    
    /// Defines how capacity is shared among connections in a group
    enum ConnectionScheduler: Sendable {
        /// Default scheduling (fair sharing)
        case `default`
        
        /// Weighted scheduling based on connection priority
        case weighted
        
        /// Prefer connections in order of creation
        case fifo
        
        /// Prefer connections based on recent activity
        case lru
    }
    
    // MARK: - Initialization
    
    init(properties: TransportProperties,
         securityParameters: SecurityParameters,
         framers: [any MessageFramer]) {
        self.sharedProperties = properties
        self.securityParameters = securityParameters
        self.framers = framers
    }
    
    // MARK: - Connection Management
    
    /// Adds a connection to the group
    func addConnection(_ connection: Connection) async {
        let connectionId = await connection.id
        connections[connectionId] = connection
    }
    
    /// Removes a connection from the group
    func removeConnection(_ connection: Connection) async {
        connections.removeValue(forKey: await connection.id)
    }
    
    /// Gets all connections in the group
    func getAllConnections() -> [Connection] {
        Array(connections.values)
    }
    
    /// Gets the count of connections in the group
    var count: Int {
        connections.count
    }
    
    /// Updates shared properties for all connections
    func updateSharedProperties(_ update: (inout TransportProperties) -> Void) async {
        update(&sharedProperties)
        
        // In a full implementation, this would propagate changes
        // to all active connections in the group
    }
    
    /// Gets the current scheduler
    func getScheduler() -> ConnectionScheduler {
        scheduler
    }
    
    /// Sets the connection scheduler
    func setScheduler(_ newScheduler: ConnectionScheduler) {
        self.scheduler = newScheduler
    }
    
    /// Gets shared properties
    func getSharedProperties() -> TransportProperties {
        sharedProperties
    }
    
    /// Gets security parameters
    func getSecurityParameters() -> SecurityParameters {
        securityParameters
    }
    
    /// Gets framers
    func getFramers() -> [any MessageFramer] {
        framers
    }
}