//
//  SimpleServer.swift
//  Example of using TAPS API for a server
//


#if !hasFeature(Embedded)
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
#endif
import TransportServices

@main
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
struct SimpleServer {
    static func main() async throws {
        // Create a server preconnection with local endpoint
        let preconnection = Preconnection(
            localEndpoints: [.tcp(port: 8080)]
        )
        
        // Start listening
        let listener = try await preconnection.listen { event in
            switch event {
            case .connectionReceived(_, let connection):
                print("New connection received")
                Task {
                    await handleConnection(connection)
                }
            case .stopped(_):
                print("Listener stopped")
            default:
                break
            }
        }
        
        print("Server listening on port 8080")
        
        // Keep server running
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
        
        // Stop listening
        await listener.stop()
    }
    
    static func handleConnection(_ connection: Connection) async {
        do {
            // Receive data
            let (data, _) = try await connection.receive()
            print("Received: \(String(data: data, encoding: .utf8) ?? "invalid")")
            
            // Send response
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, World!"
            try await connection.send(data: Data(response.utf8))
            
            // Close connection
            await connection.close()
        } catch {
            print("Error handling connection: \(error)")
        }
    }
}