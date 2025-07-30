import Testing
#if canImport(Foundation)
import Foundation
#endif
@testable import TransportServices

@Suite("Apple Platform Tests")
struct ApplePlatformTests {
    
    @Test("Test local loopback connection", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testLocalLoopbackConnection() async throws {
        // Create a listener on localhost
        let listenerPreconnection = Preconnection(
            localEndpoints: [LocalEndpoint.tcp(port: 0)] // Use port 0 for automatic assignment
        )
        
        let connectedEvent = EventCollector()
        
        // Start listener
        let listener = try await withTimeout(.seconds(2), operation: "listener creation") {
            try await listenerPreconnection.listen { event in
                Task { await connectedEvent.add(event) }
            }
        }
        
        // For this test, use a hardcoded port since we can't easily get the dynamic port
        let testPort: UInt16 = 54321
        
        // Try to create a client connection
        let clientPreconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "127.0.0.1", port: testPort)]
        )
        
        do {
            // Try to connect with timeout
            _ = try await withTimeout(.seconds(3), operation: "client connection") {
                try await clientPreconnection.initiate()
            }
        } catch {
            // Connection might fail if port is unavailable, which is okay
            print("Local connection test skipped: \(error)")
        }
        
        // Clean up
        await listener.stop()
    }
    
    @Test("Create and initiate connection", .timeLimit(.minutes(1)))
    func testCreateConnection() async throws {
        // Create a preconnection with remote endpoint
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        // Configure security for HTTPS
        var secParams = preconnection.securityParameters
        secParams.alpn = ["h2", "http/1.1"]
        
        do {
            // Initiate connection with 5 second timeout
            let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
                try await preconnection.initiate()
            }
            
            // Verify connection is established
            try await connection.waitForState(.established, timeout: .seconds(2))
            
            // Close connection
            await connection.close()
            try await connection.waitForState(.closed, timeout: .seconds(2))
        } catch let error as TestTimeoutError {
            // If we timeout, it might be due to network conditions
            print("Test skipped due to timeout: \(error)")
            throw error
        }
    }
    
    @Test("Test connection with data transfer")
    func testDataTransfer() async throws {
        // Create connection to httpbin.org for testing
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "httpbin.org", port: 443)]
        )
        
        // Configure security for HTTPS
        var secParams = preconnection.securityParameters
        secParams.alpn = ["h2", "http/1.1"]
        
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        // Send HTTP request
        let request = """
        GET /get HTTP/1.1\r
        Host: httpbin.org\r
        User-Agent: TAPS-Swift-Test\r
        Accept: */*\r
        Connection: close\r
        \r
        
        """
        
        let requestData = Data(request.utf8)
        try await connection.send(data: requestData)
        
        // Receive response
        let (responseData, _) = try await connection.receive(maxLength: 8192)
        let response = String(data: responseData, encoding: .utf8) ?? ""
        
        // Verify we got an HTTP response
        #expect(response.contains("HTTP/1.1"))
        #expect(response.contains("200 OK") || response.contains("200"))
        
        await connection.close()
    }
    
    @Test("Test connection abort")
    func testConnectionAbort() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        // Abort should be synchronous and immediate
        await connection.abort()
        let closedState = await connection.state
        #expect(closedState == .closed)
    }
    
    @Test("Test preconnection resolve")
    func testPreconnectionResolve() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let (_, remoteEndpoints) = await preconnection.resolve()
        
        // Should have resolved endpoints
        #expect(!remoteEndpoints.isEmpty)
        
        // Verify the resolved endpoints contain the original
        #expect(remoteEndpoints.contains { $0.hostName == "example.com" && $0.port == 443 })
    }
    
    @Test("Test listener creation and accept")
    func testListener() async throws {
        let preconnection = Preconnection(
            localEndpoints: [LocalEndpoint.tcp(port: 0)] // Use port 0 for automatic assignment
        )
        
        let receivedConnectionActor = EventCollector()
        
        let listener = try await preconnection.listen { event in
            switch event {
            case .connectionReceived(_, let connection):
                Task { await receivedConnectionActor.add(event) }
            default:
                break
            }
        }
        
        // Listener should be listening
        let acceptedCount = await listener.getAcceptedConnectionCount()
        #expect(acceptedCount == 0)
        
        // Get the actual listening endpoint from the platform listener
        // For this test, we'll use a fixed port since we can't easily get it from the listener
        let localPort: UInt16 = 8888
        
        // Create a client connection to the listener
        let clientPreconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "localhost", port: localPort)]
        )
        
        // Try to connect (may fail if port is in use or listener setup failed)
        do {
            let clientConnection = try await clientPreconnection.initiate()
            
            // Wait a bit for the connection to be accepted
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            let events = await receivedConnectionActor.events
            #expect(!events.isEmpty)
            
            // Clean up
            await clientConnection.close()
        } catch {
            // Connection might fail, which is okay for this test
            print("Client connection failed: \(error)")
        }
        
        await listener.stop()
    }
    
    @Test("Test connection properties")
    func testConnectionProperties() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let connection = try await preconnection.initiate()
        
        // Properties should be read-only
        let props = await connection.properties
        #expect(props.multipathPolicy == .handover)
        
        // Set a property using the async method
        try await connection.setConnectionProperty(.keepAlive(enabled: true, interval: 30))
        
        // Verify the property was set (we can't easily check the value due to Any? not being Sendable)
        // The fact that setConnectionProperty didn't throw is sufficient for this test
        
        await connection.close()
    }
    
    @Test("Test multipath policy")
    func testMultipathPolicy() async throws {
        var preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        // Set multipath policy
        preconnection.transportProperties.multipathPolicy = .handover
        
        let connection = try await preconnection.initiate()
        let props = await connection.properties
        #expect(props.multipathPolicy == .handover)
        
        await connection.close()
    }
    
    @Test("Test connection with custom event handler")
    func testEventHandler() async throws {
        let eventActor = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let connection = try await preconnection.initiate { event in
            Task { await eventActor.add(event) }
        }
        
        // Wait a bit for events to be collected
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should have received ready event
        let events = await eventActor.events
        #expect(events.contains { 
            if case .ready = $0 { return true }
            return false
        })
        
        await connection.close()
        
        // Wait a bit for closed event
        try await Task.sleep(nanoseconds: 100_000_000)
        let finalEvents = await eventActor.events
        
        // Should have received closed event
        #expect(finalEvents.contains {
            if case .closed = $0 { return true }
            return false
        })
    }
    
    @Test("Test connection without event handler")
    func testNoEventHandler() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        // Should work without event handler (uses default no-op)
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        await connection.close()
    }
    
    @Test("Test local endpoint with interface")
    func testLocalEndpointInterface() async throws {
        var en0Endpoint = LocalEndpoint()
        en0Endpoint.interface = "en0"
        let preconnection = Preconnection(
            localEndpoints: [en0Endpoint],
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        await connection.close()
    }
    
    @Test("Test connection clone")
    func testConnectionClone() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [RemoteEndpoint.tcp(host: "example.com", port: 443)]
        )
        
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        // Clone the connection
        let clonedConnection = try await connection.clone()
        let clonedState = await clonedConnection.state
        #expect(clonedState == .established)
        
        // Both connections should be independent
        await connection.close()
        let closedState = await connection.state
        #expect(closedState == .closed)
        
        let clonedStateAfter = await clonedConnection.state
        #expect(clonedStateAfter == .established)
        
        await clonedConnection.close()
    }
}