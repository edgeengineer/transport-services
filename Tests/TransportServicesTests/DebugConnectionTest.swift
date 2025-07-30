//
//  DebugConnectionTest.swift
//  
//
//  Debug test to trace connection flow
//

import Testing
#if canImport(Foundation)
import Foundation
#endif
@testable import TransportServices

@Suite("Debug Connection Test")
struct DebugConnectionTest {
    
    @Test("Debug connection flow")
    func testDebugConnection() async throws {
        print("Starting debug connection test")
        
        // Create a simple preconnection
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "localhost", port: 8080)]
        )
        
        print("Created preconnection")
        
        do {
            print("Attempting to initiate connection...")
            
            // Try with a very short timeout first
            let connection = try await withTimeout(.seconds(2), operation: "debug connection") {
                print("Inside withTimeout block")
                return try await preconnection.initiate { event in
                    print("Event received: \(event)")
                }
            }
            
            print("Connection created successfully")
            let state = await connection.state
            print("Connection state: \(state)")
            
            await connection.close()
            print("Connection closed")
            
        } catch {
            print("Connection failed with error: \(error)")
            // This is expected if localhost:8080 is not listening
        }
    }
}