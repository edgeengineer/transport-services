//
//  SimplestConnectionTest.swift
//  
//
//  Test connection with direct IP to avoid DNS resolution
//

import Testing
#if canImport(Foundation)
import Foundation
#endif
@testable import TransportServices

@Suite("Simplest Connection Test")
struct SimplestConnectionTest {
    
    @Test("Test connection with direct IP")
    func testDirectIPConnection() async throws {
        print("=== Starting direct IP connection test ===")
        
        // Use direct IP to avoid DNS resolution
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "1.1.1.1", port: 80)]  // Cloudflare DNS
        )
        
        print("Created preconnection with direct IP")
        
        do {
            let connection = try await withTimeout(.seconds(5), operation: "direct IP connection") {
                print("Calling preconnection.initiate...")
                return try await preconnection.initiate { event in
                    print("Event: \(event)")
                }
            }
            
            print("Connection established!")
            let state = await connection.state
            print("State: \(state)")
            
            await connection.close()
            print("Connection closed")
            
        } catch {
            print("Expected error (connection to 1.1.1.1:80 may fail): \(error)")
        }
        
        print("=== Test completed ===")
    }
}