
#if !hasFeature(Embedded)
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
#endif
/// Represents a group of related connections
public actor ConnectionGroup {
    private var connections: [any Connection] = []
    private weak var scheduler: ConnectionGroupScheduler?
    
    public init(scheduler: ConnectionGroupScheduler? = nil) {
        self.scheduler = scheduler
    }
    
    /// Add a connection to the group
    func addConnection(_ connection: any Connection) {
        connections.append(connection)
    }
    
    /// Remove a connection from the group
    func removeConnection(_ connection: any Connection) {
        connections.removeAll { existingConnection in
            // Compare by identity since actors are reference types
            return (existingConnection as AnyObject) === (connection as AnyObject)
        }
    }
    
    /// The number of connections in the group
    public var connectionCount: Int {
        connections.count
    }
    
    /// Close all connections in the group
    public func closeGroup() async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for connection in connections {
                taskGroup.addTask {
                    await connection.close()
                }
            }
        }
    }
    
    /// Abort all connections in the group
    public func abortGroup() {
        // Create a task to abort all connections concurrently
        Task {
            await withTaskGroup(of: Void.self) { taskGroup in
                for connection in connections {
                    taskGroup.addTask {
                        await connection.abort()
                    }
                }
            }
        }
    }
}