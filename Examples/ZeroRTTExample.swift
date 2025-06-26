import TransportServices
import Foundation

/// 0-RTT Connection Example
///
/// This example demonstrates:
/// - Using InitiateWithSend for 0-RTT connections
/// - Ensuring messages are safely replayable
/// - Optimizing connection establishment latency
/// - Fallback handling when 0-RTT fails

@main
struct ZeroRTTExample {
    static func main() async {
        do {
            // Example 1: Basic 0-RTT connection
            await basic0RTTConnection()
            
            // Example 2: 0-RTT with session resumption
            await sessionResumption0RTT()
            
            // Example 3: Handling 0-RTT rejection
            await handle0RTTRejection()
            
        } catch {
            print("Error: \(error)")
        }
    }
    
    // MARK: - Basic 0-RTT Connection
    
    static func basic0RTTConnection() async {
        do {
            print("\n=== Basic 0-RTT Example ===")
            
            var endpoint = RemoteEndpoint(kind: .host("example.com"))
            endpoint.port = 443
            
            // Create a safely replayable message
            let request = createSafeRequest()
            
            // Configure for 0-RTT
            var transport = TransportProperties.lowLatency()
            transport.zeroRTT = .prefer
            
            let preconnection = Preconnection(
                remote: [endpoint],
                transport: transport
            )
            
            print("Initiating 0-RTT connection with first message...")
            let startTime = Date()
            
            // Initiate with first message (0-RTT if supported)
            let connection = try await preconnection.initiateWithSend(request)
            
            let connectionTime = Date().timeIntervalSince(startTime)
            print("Connected in \(connectionTime * 1000)ms (0-RTT likely used)")
            
            // Receive response
            let response = try await connection.receive()
            print("Received response of \(response.data.count) bytes")
            
            await connection.close()
            
        } catch {
            print("0-RTT error: \(error)")
        }
    }
    
    // MARK: - Session Resumption 0-RTT
    
    static func sessionResumption0RTT() async {
        do {
            print("\n=== Session Resumption 0-RTT Example ===")
            
            var endpoint = RemoteEndpoint(kind: .host("api.example.com"))
            endpoint.port = 443
            
            var transport = TransportProperties()
            transport.zeroRTT = .prefer
            
            // First connection to establish session
            print("Establishing initial connection...")
            let preconnection1 = Preconnection(
                remote: [endpoint],
                transport: transport
            )
            
            let connection1 = try await preconnection1.initiate()
            
            // Send some data to establish session
            let setupMsg = Message("GET /session HTTP/1.1\r\n\r\n".data(using: .utf8)!)
            try await connection1.send(setupMsg)
            _ = try await connection1.receive()
            
            await connection1.close()
            print("Initial connection closed, session established")
            
            // Second connection with 0-RTT using session resumption
            print("\nResuming with 0-RTT...")
            
            let request = createSafeRequest()
            let preconnection2 = Preconnection(
                remote: [endpoint],
                transport: transport
            )
            
            let startTime = Date()
            let connection2 = try await preconnection2.initiateWithSend(request)
            let resumeTime = Date().timeIntervalSince(startTime)
            
            print("Resumed in \(resumeTime * 1000)ms with 0-RTT")
            
            await connection2.close()
            
        } catch {
            print("Session resumption error: \(error)")
        }
    }
    
    // MARK: - Handle 0-RTT Rejection
    
    static func handle0RTTRejection() async {
        do {
            print("\n=== 0-RTT Rejection Handling Example ===")
            
            var endpoint = RemoteEndpoint(kind: .host("strict.example.com"))
            endpoint.port = 443
            
            // Create a message that might be rejected for replay
            var message = Message("POST /api/data HTTP/1.1\r\n\r\n".data(using: .utf8)!)
            message.context.safelyReplayable = true  // Mark as safe even though POST
            
            var transport = TransportProperties()
            transport.zeroRTT = .require  // Require 0-RTT
            
            let preconnection = Preconnection(
                remote: [endpoint],
                transport: transport
            )
            
            do {
                print("Attempting 0-RTT with potentially unsafe message...")
                let connection = try await preconnection.initiateWithSend(message)
                print("0-RTT accepted")
                await connection.close()
                
            } catch TransportError.establishmentFailure(let reason) {
                print("0-RTT rejected: \(reason)")
                
                // Fallback to regular connection
                print("Falling back to standard connection...")
                transport.zeroRTT = .prohibit
                
                let fallbackPreconnection = Preconnection(
                    remote: [endpoint],
                    transport: transport
                )
                
                let connection = try await fallbackPreconnection.initiate()
                try await connection.send(message)
                print("Message sent via standard connection")
                await connection.close()
            }
            
        } catch {
            print("Rejection handling error: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
    static func createSafeRequest() -> Message {
        // Create an idempotent GET request (safe to replay)
        let request = """
        GET /api/data HTTP/1.1\r
        Host: example.com\r
        X-Request-ID: \(UUID().uuidString)\r
        \r
        """
        
        var message = Message(request.data(using: .utf8)!)
        message.context.safelyReplayable = true  // Mark as replay-safe
        return message
    }
}

// Production 0-RTT Usage:
/*
class API0RTTClient {
    private let endpoint: RemoteEndpoint
    private let transport: TransportProperties
    
    init(host: String, port: UInt16) {
        var endpoint = RemoteEndpoint(kind: .host(host))
        endpoint.port = port
        self.endpoint = endpoint
        
        // Configure for 0-RTT with fallback
        var transport = TransportProperties.lowLatency()
        transport.zeroRTT = .prefer  // Not require, to allow fallback
        self.transport = transport
    }
    
    func getResource(path: String) async throws -> Data {
        // Only use 0-RTT for idempotent GET requests
        let request = createGETRequest(path: path)
        
        let preconnection = Preconnection(
            remote: [endpoint],
            transport: transport
        )
        
        // Try 0-RTT first
        let connection: Connection
        do {
            connection = try await preconnection.initiateWithSend(request)
            print("0-RTT connection established")
        } catch {
            // Fallback to regular connection
            print("0-RTT failed, using standard connection")
            connection = try await preconnection.initiate()
            try await connection.send(request)
        }
        
        let response = try await connection.receive()
        await connection.close()
        
        return response.data
    }
    
    func postData(path: String, data: Data) async throws -> Data {
        // Never use 0-RTT for non-idempotent operations
        var transport = self.transport
        transport.zeroRTT = .prohibit
        
        let preconnection = Preconnection(
            remote: [endpoint],
            transport: transport
        )
        
        let connection = try await preconnection.initiate()
        
        let request = createPOSTRequest(path: path, body: data)
        try await connection.send(request)
        
        let response = try await connection.receive()
        await connection.close()
        
        return response.data
    }
    
    private func createGETRequest(path: String) -> Message {
        let request = """
        GET \(path) HTTP/1.1\r
        Host: \(endpoint.kind)\r
        Accept: application/json\r
        X-Request-ID: \(UUID().uuidString)\r
        \r
        """
        
        var message = Message(request.data(using: .utf8)!)
        message.context.safelyReplayable = true
        return message
    }
    
    private func createPOSTRequest(path: String, body: Data) -> Message {
        let header = """
        POST \(path) HTTP/1.1\r
        Host: \(endpoint.kind)\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        \r
        """
        
        var message = Message(header.data(using: .utf8)! + body)
        message.context.safelyReplayable = false  // POST is not idempotent
        return message
    }
}
*/