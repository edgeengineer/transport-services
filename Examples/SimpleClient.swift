//
//  SimpleClient.swift
//  Example of using TAPS API
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
struct SimpleClient {
    static func main() async throws {
        // Create a preconnection with TLS
        let preconnection = Preconnection(
            remoteEndpoints: [.tcp(host: "example.com", port: 443)],
            securityParameters: SecurityParameters() // TLS by default
        )
        
        // Or create one without TLS
        let _ = Preconnection(
            remoteEndpoints: [.tcp(host: "example.com", port: 80)],
            transportProperties: TransportProperties()
        )
        
        // Initiate connection
        let connection = try await preconnection.initiate { event in
            switch event {
            case .ready(_):
                print("Connection ready")
            case .connectionError(_, let reason):
                print("Connection error: \(reason ?? "unknown")")
            case .closed(_):
                print("Connection closed")
            default:
                break
            }
        }
        
        // Send data
        let message = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
        try await connection.send(data: Data(message.utf8))
        
        // Receive response
        let (data, _) = try await connection.receive()
        print("Received: \(String(data: data, encoding: .utf8) ?? "invalid")")
        
        // Close connection
        await connection.close()
    }
}