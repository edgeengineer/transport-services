import TransportServices
import Foundation

/// Simple TCP-like Client Example
///
/// This example demonstrates:
/// - Creating a basic client connection
/// - Sending and receiving messages
/// - Proper error handling
/// - Clean connection shutdown

@main
struct SimpleClient {
    static func main() async {
        do {
            // Create a remote endpoint for the server
            var remoteEndpoint = RemoteEndpoint(kind: .host("example.com"))
            remoteEndpoint.port = 443
            
            // Create a preconnection with default TCP-like properties
            let preconnection = Preconnection(
                remote: [remoteEndpoint],
                transport: .reliableStream(),
                security: SecurityParameters() // Default TLS
            )
            
            print("Connecting to \(remoteEndpoint.kind)...")
            
            // Initiate the connection
            let connection = try await preconnection.initiate()
            
            print("Connected successfully!")
            
            // Send a message
            let request = Message("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".data(using: .utf8)!)
            try await connection.send(request)
            
            print("Request sent, waiting for response...")
            
            // Receive response
            let response = try await connection.receive()
            if let responseText = String(data: response.data, encoding: .utf8) {
                print("Received response:")
                print(responseText.prefix(200) + "...")
            }
            
            // Close the connection gracefully
            await connection.close()
            
            print("Connection closed.")
            
        } catch {
            print("Error: \(error)")
        }
    }
}

// Example usage in a real application:
/*
class NetworkClient {
    private var connection: Connection?
    
    func connect(to host: String, port: UInt16) async throws {
        var endpoint = RemoteEndpoint(kind: .host(host))
        endpoint.port = port
        
        let preconnection = Preconnection(
            remote: [endpoint],
            transport: .reliableStream()
        )
        
        self.connection = try await preconnection.initiate()
    }
    
    func send(_ data: Data) async throws {
        guard let connection = connection else {
            throw TransportError.sendFailure("Not connected")
        }
        
        let message = Message(data)
        try await connection.send(message)
    }
    
    func receive() async throws -> Data {
        guard let connection = connection else {
            throw TransportError.receiveFailure("Not connected")
        }
        
        let message = try await connection.receive()
        return message.data
    }
    
    func disconnect() async {
        await connection?.close()
        connection = nil
    }
}
*/