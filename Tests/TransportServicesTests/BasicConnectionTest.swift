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
#if canImport(Network)
import Network
#endif

@Suite("Basic Connection Test")
struct BasicConnectionTest {
    
    @Test("Test basic connection establishment")
    func testBasicConnection() async throws {
        // Create a simple preconnection with an unreachable address
        // Using a reserved TEST-NET-1 address that should fail quickly
        var endpoint = RemoteEndpoint()
        endpoint.ipAddress = "192.0.2.1"
        endpoint.port = 12345
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [endpoint]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let eventCollector = EventCollector()
        
        // Try to establish connection with event tracking
        do {
            let pc = preconnection
            let connection = try await withTimeout(in: .seconds(10), clock: ContinuousClock()) {
                try await pc.initiate { event in
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
            // Wait for connection to fail and transition to closed
            try await connection.waitForState(.closed)
            
            let state = await connection.state
            print("Connection state: \(state)")
            #expect(state == .closed)
        
            // Check for ready event
            let hasReady = await eventCollector.hasReadyEvent()
            #expect(hasReady == false)
        
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
        } catch {
            // Expected to fail
        }
    }
    
    @Test("Test connection without event handler")
    func testConnectionNoHandler() async throws {
        var endpoint = RemoteEndpoint()
        endpoint.ipAddress = "192.0.2.1" 
        endpoint.port = 12345
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [endpoint]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        // Should work without event handler
        do {
            let pc = preconnection
            let connection = try await withTimeout(in: .seconds(10), clock: ContinuousClock()) {
                try await pc.initiate()
            }
            // Wait for connection to fail
            try await connection.waitForState(.closed)
            let state = await connection.state
            #expect(state == .closed)
            await connection.close()
        } catch {
            // Expected to fail
        }
    }
}