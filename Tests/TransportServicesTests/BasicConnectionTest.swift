//
//  BasicConnectionTest.swift
//  
//
//  Basic test to verify connection establishment works
//

import Testing
#if canImport(Foundation)
import Foundation
#endif
@testable import TransportServices

@Suite("Basic Connection Test")
struct BasicConnectionTest {
    
    @Test("Test basic connection establishment")
    func testBasicConnection() async throws {
        // Create a simple preconnection
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let eventCollector = EventCollector()
        
        // Try to establish connection with event tracking
        let connection = try await withTimeout(.seconds(10), operation: "basic connection") {
            try await preconnection.initiate { event in
                Task {
                    await eventCollector.add(event)
                    switch event {
                    case .ready:
                        print("Connection ready!")
                    case .closed:
                        print("Connection closed!")
                    case .connectionError(_, let reason):
                        print("Connection error: \(reason ?? "unknown")")
                    default:
                        print("Other event: \(event)")
                    }
                }
            }
        }
        
        // Check state
        let state = await connection.state
        print("Connection state: \(state)")
        #expect(state == .established)
        
        // Check for ready event
        let hasReady = await eventCollector.hasReadyEvent()
        #expect(hasReady == true)
        
        // Close connection
        await connection.close()
        
        // Give some time for close event
        try await Task.sleep(for: .milliseconds(100))
        
        let finalState = await connection.state
        print("Final state: \(finalState)")
        #expect(finalState == .closed)
        
        // Check for closed event
        let hasClosed = await eventCollector.hasClosedEvent()
        #expect(hasClosed == true)
    }
    
    @Test("Test connection without event handler")
    func testConnectionNoHandler() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        // Should work without event handler
        let connection = try await withTimeout(.seconds(10), operation: "connection without handler") {
            try await preconnection.initiate()
        }
        
        let state = await connection.state
        #expect(state == .established)
        
        await connection.close()
    }
}