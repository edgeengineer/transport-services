import TransportServices
import Foundation

/// Connection Group Example
///
/// This example demonstrates:
/// - Creating connection groups for multistreaming
/// - Cloning connections within a group
/// - Managing shared properties across grouped connections
/// - Using different connection schedulers

@main
struct ConnectionGroupExample {
    static func main() async {
        do {
            // Create initial connection to a server
            var endpoint = RemoteEndpoint(kind: .host("example.com"))
            endpoint.port = 443
            
            let preconnection = Preconnection(
                remote: [endpoint],
                transport: .reliableStream()
            )
            
            print("Establishing primary connection...")
            let primaryConnection = try await preconnection.initiate()
            
            // Clone the connection to create a group
            print("Creating connection group with cloned connections...")
            
            // Clone for parallel data streams
            let dataStream1 = try await primaryConnection.clone(
                framer: nil,
                altering: TransportProperties() // Inherits properties
            )
            
            let dataStream2 = try await primaryConnection.clone(
                framer: nil,
                altering: TransportProperties()
            )
            
            // Create a high-priority control stream
            var controlProperties = TransportProperties()
            // In a real implementation, set priority
            let controlStream = try await primaryConnection.clone(
                framer: nil,
                altering: controlProperties
            )
            
            print("Connection group created with 4 connections")
            
            // Use the connections concurrently
            await withTaskGroup(of: Void.self) { group in
                // Send data on stream 1
                group.addTask {
                    do {
                        let data = Message("Data stream 1".data(using: .utf8)!)
                        try await dataStream1.send(data)
                        print("Sent on data stream 1")
                    } catch {
                        print("Error on stream 1: \(error)")
                    }
                }
                
                // Send data on stream 2
                group.addTask {
                    do {
                        let data = Message("Data stream 2".data(using: .utf8)!)
                        try await dataStream2.send(data)
                        print("Sent on data stream 2")
                    } catch {
                        print("Error on stream 2: \(error)")
                    }
                }
                
                // Send control message
                group.addTask {
                    do {
                        let control = Message("Control message".data(using: .utf8)!)
                        try await controlStream.send(control)
                        print("Sent control message")
                    } catch {
                        print("Error on control stream: \(error)")
                    }
                }
            }
            
            // Query grouped connections
            let allConnections = await primaryConnection.groupedConnections
            print("Total connections in group: \(allConnections.count)")
            
            // Close entire group at once
            print("Closing connection group...")
            await primaryConnection.closeGroup()
            
            print("All connections closed")
            
        } catch {
            print("Error: \(error)")
        }
    }
}

// Advanced connection group usage:
/*
class MultistreamProtocol {
    private var controlConnection: Connection?
    private var dataConnections: [Connection] = []
    private let maxDataStreams = 4
    
    func connect(to endpoint: RemoteEndpoint) async throws {
        // Establish primary connection
        let preconnection = Preconnection(
            remote: [endpoint],
            transport: .reliableStream()
        )
        
        controlConnection = try await preconnection.initiate()
        
        // Create data streams based on available bandwidth
        for i in 0..<maxDataStreams {
            let dataStream = try await controlConnection!.clone(
                framer: nil,
                altering: nil
            )
            dataConnections.append(dataStream)
        }
    }
    
    func sendData(_ data: Data) async throws {
        // Round-robin across data streams
        let streamIndex = Int.random(in: 0..<dataConnections.count)
        let connection = dataConnections[streamIndex]
        
        let message = Message(data)
        try await connection.send(message)
    }
    
    func sendControl(_ command: String) async throws {
        guard let control = controlConnection else {
            throw TransportError.sendFailure("No control connection")
        }
        
        let message = Message(command.data(using: .utf8)!)
        try await control.send(message)
    }
    
    func disconnect() async {
        // Closing the primary connection closes the entire group
        await controlConnection?.closeGroup()
        controlConnection = nil
        dataConnections.removeAll()
    }
}
*/