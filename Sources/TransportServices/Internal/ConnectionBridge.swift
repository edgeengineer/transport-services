#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOPosix

/// Bridge between the public Connection actor and the internal implementation.
///
/// This class provides a concrete implementation of the Connection actor
/// that delegates to the internal ConnectionImpl.
final class ConnectionBridge {
    
    // MARK: - Properties
    
    /// The internal implementation
    private let impl: ConnectionImpl
    
    /// Cached ID to avoid async access
    let id: UUID
    
    /// The owning connection (set after creation)
    private weak var owningConnection: Connection?
    
    // MARK: - Initialization
    
    init(impl: ConnectionImpl) {
        self.impl = impl
        self.id = impl.id
    }
    
    func setOwningConnection(_ connection: Connection) {
        self.owningConnection = connection
    }
    
    // MARK: - State Access
    
    func getState() async -> ConnectionState {
        await impl.state
    }
    
    func getProperties() async -> TransportProperties {
        impl.properties
    }
    
    func getRemoteEndpoint() async -> RemoteEndpoint {
        await impl.remoteEndpoint ?? RemoteEndpoint(kind: .host("unknown"))
    }
    
    func getLocalEndpoint() async -> LocalEndpoint {
        await impl.localEndpoint ?? LocalEndpoint(kind: .host("unknown"))
    }
    
    // MARK: - Operations
    
    func send(_ message: Message) async throws {
        try await impl.send(message)
    }
    
    func sendPartial(_ slice: Data, context: MessageContext, endOfMessage: Bool) async throws {
        let message = Message(slice, context: context)
        try await impl.send(message)
    }
    
    func receive(minIncomplete: Int, max: Int) async throws -> Message {
        try await impl.receive()
    }
    
    func createIncomingMessageStream() -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    while await impl.state == .established {
                        let message = try await impl.receive()
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func clone(framer: (any MessageFramer)?, altering transport: TransportProperties?) async throws -> Connection {
        let clonedImpl = try await impl.clone(altering: transport, framer: framer)
        let bridge = ConnectionBridge(impl: clonedImpl)
        let connection = Connection()
        await connection.setBridge(bridge)
        
        // The cloned implementation should have the group set by impl.clone()
        if let group = await clonedImpl.getConnectionGroup() {
            // Add the original connection to the group if it's not already there
            if let originalConnection = owningConnection {
                await group.addConnection(originalConnection)
            }
            // Add the cloned connection to the group
            await group.addConnection(connection)
        }
        
        return connection
    }
    
    func getGroupedConnections() async -> [Connection] {
        guard let group = await impl.getConnectionGroup() else {
            // If no group exists, return just this connection if we have it
            if let connection = owningConnection {
                return [connection]
            }
            return []
        }
        return await group.getAllConnections()
    }
    
    func close() async {
        await impl.close()
    }
    
    func closeGroup() async {
        guard let group = await impl.getConnectionGroup() else {
            await impl.close()
            return
        }
        
        let connections = await group.getAllConnections()
        await withTaskGroup(of: Void.self) { taskGroup in
            for connection in connections {
                taskGroup.addTask {
                    await connection.close()
                }
            }
        }
    }
    
    func abort() async {
        await impl.abort()
    }
    
    func abortGroup() async {
        guard let group = await impl.getConnectionGroup() else {
            await impl.abort()
            return
        }
        
        let connections = await group.getAllConnections()
        await withTaskGroup(of: Void.self) { taskGroup in
            for connection in connections {
                taskGroup.addTask {
                    await connection.abort()
                }
            }
        }
    }
}

/// Extension to make ConnectionBridge Sendable
extension ConnectionBridge: @unchecked Sendable {}