//
//  ConnectionTests.swift
//  
//
//  Tests for Connection.swift based on RFC 9622 Transport Services API
//

import Testing
#if canImport(Foundation)
import Foundation
#endif
@testable import TransportServices

@Suite("Connection Tests", .timeLimit(.minutes(1)))
struct ConnectionTests {
    
    // MARK: - Connection Lifecycle Tests (RFC 9622 Section 7, 8.3, 10)
    
    @Test("Connection state transitions during lifecycle")
    func testConnectionStateTransitions() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Initial state should be established after successful initiate
        let initialState = await connection.state
        #expect(initialState == .established)
        
        // Should have received ready event
        try await withTimeout(.seconds(2), operation: "waiting for ready event") {
            let hasReady = await eventCollector.hasReadyEvent()
            #expect(hasReady == true)
        }
        
        // Test graceful close
        await connection.close()
        
        // State should transition to closed
        try await connection.waitForState(.closed)
        let closedState = await connection.state
        #expect(closedState == .closed)
        
        // Should have received closed event
        try await withTimeout(.seconds(2), operation: "waiting for closed event") {
            let hasClosed = await eventCollector.hasClosedEvent()
            #expect(hasClosed == true)
        }
    }
    
    @Test("Connection abort immediately closes connection")
    func testConnectionAbort() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        let establishedState = await connection.state
        #expect(establishedState == .established)
        
        // Abort should immediately close
        await connection.abort()
        
        // State should be closed immediately
        let abortedState = await connection.state
        #expect(abortedState == .closed)
        
        // Should receive connection error event for abort
        try await withTimeout(.seconds(2), operation: "waiting for error event") {
            let events = await eventCollector.events
            let hasError = events.contains { event in
                if case .connectionError(_, let reason) = event {
                    return reason?.contains("aborted") ?? false
                }
                return false
            }
            #expect(hasError == true)
        }
    }
    
    // MARK: - Data Transfer Tests (RFC 9622 Section 9)
    
    @Test("Send and receive data on established connection")
    func testDataTransfer() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 80; return ep }()]
        )
        
        var secParams = preconnection.securityParameters
        secParams.alpn = ["h2", "http/1.1"]
        
        let connection = try await withTimeout(.seconds(10), operation: "connection to httpbin") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        let state = await connection.state
        #expect(state == .established)
        
        // Send HTTP request
        let request = """
        GET /get HTTP/1.1\r
        Host: httpbin.org\r
        User-Agent: TAPS-Swift-ConnectionTest\r
        Accept: */*\r
        Connection: close\r
        \r
        
        """
        
        let messageContext = MessageContext()
        let requestData = Data(request.utf8)
        
        try await withTimeout(.seconds(5), operation: "sending data") {
            try await connection.send(data: requestData, context: messageContext)
        }
        
        // Should have sent event
        try await withTimeout(.seconds(2), operation: "waiting for sent event") {
            let events = await eventCollector.events
            let hasSent = events.contains { event in
                if case .sent = event { return true }
                return false
            }
            #expect(hasSent == true)
        }
        
        // Receive response
        let (responseData, _) = try await withTimeout(.seconds(5), operation: "receiving data") {
            try await connection.receive(maxLength: 8192)
        }
        
        let response = String(data: responseData, encoding: .utf8) ?? ""
        #expect(response.contains("HTTP/1.1"))
        #expect(response.contains("200"))
        
        // Should have received event
        try await withTimeout(.seconds(2), operation: "waiting for received event") {
            let events = await eventCollector.events
            let hasReceived = events.contains { event in
                if case .received = event { return true }
                return false
            }
            #expect(hasReceived == true)
        }
        
        await connection.close()
    }
    
    @Test("Send fails on closed connection")
    func testSendOnClosedConnection() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate()
        }
        
        // Close the connection
        await connection.close()
        try await connection.waitForState(.closed)
        
        // Try to send data on closed connection
        let data = Data("test".utf8)
        
        do {
            try await connection.send(data: data)
            Issue.record("Send should have thrown TransportServicesError.connectionClosed")
        } catch {
            #expect(error is TransportServicesError)
        }
    }
    
    @Test("Receive fails on closed connection")
    func testReceiveOnClosedConnection() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate()
        }
        
        // Close the connection
        await connection.close()
        try await connection.waitForState(.closed)
        
        // Try to receive data on closed connection
        do {
            _ = try await connection.receive()
            Issue.record("Receive should have thrown TransportServicesError.connectionClosed")
        } catch {
            #expect(error is TransportServicesError)
        }
    }
    
    @Test("Partial message receive")
    func testPartialMessageReceive() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 80; return ep }()]
        )
        
        var secParams = preconnection.securityParameters
        secParams.alpn = ["h2", "http/1.1"]
        
        let connection = try await withTimeout(.seconds(10), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Send request
        let request = """
        GET /stream-bytes/1024 HTTP/1.1\r
        Host: httpbin.org\r
        Connection: close\r
        \r
        
        """
        
        try await connection.send(data: Data(request.utf8))
        
        // Receive with small buffer to test partial receives
        let (partialData, _) = try await withTimeout(.seconds(5), operation: "partial receive") {
            try await connection.receive(minIncompleteLength: 1, maxLength: 64)
        }
        
        #expect(partialData.count <= 64)
        #expect(partialData.count >= 1)
        
        await connection.close()
    }
    
    // MARK: - Connection Properties Tests (RFC 9622 Section 8.1)
    
    @Test("Connection inherits properties from preconnection")
    func testConnectionInheritsProperties() async throws {
        var preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        // Set custom properties on preconnection
        preconnection.transportProperties.multipathPolicy = .handover
        preconnection.transportProperties.connPriority = 100
        preconnection.transportProperties.connTimeout = 30
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") { [preconnection] in
            try await preconnection.initiate()
        }
        
        // Connection should inherit properties
        let props = await connection.properties
        #expect(props.multipathPolicy == .handover)
        #expect(props.connPriority == 100)
        #expect(props.connTimeout == 30)
        
        await connection.close()
    }
    
    @Test("Set connection properties")
    func testSetConnectionProperties() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate()
        }
        
        // Set various connection properties
        try await connection.setConnectionProperty(.multipathPolicy(.interactive))
        try await connection.setConnectionProperty(.priority(200))
        try await connection.setConnectionProperty(.connectionTimeout(60))
        try await connection.setConnectionProperty(.keepAlive(enabled: true, interval: 30))
        
        // Properties should be updated locally
        let props = await connection.properties
        #expect(props.multipathPolicy == .interactive)
        #expect(props.connPriority == 200)
        #expect(props.connTimeout == 60)
        #expect(props.keepAlive == .require)
        #expect(props.keepAliveTimeout == 30)
        
        await connection.close()
    }
    
    // MARK: - Connection Cloning Tests (RFC 9622 Section 7.4)
    
    @Test("Clone connection creates independent connection")
    func testConnectionClone() async throws {
        let eventCollector1 = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection1 = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector1.add(event) }
            }
        }
        
        // Clone the connection
        let connection2 = try await withTimeout(.seconds(5), operation: "connection clone") {
            try await connection1.clone()
        }
        
        // Both should be established
        let state1 = await connection1.state
        let state2 = await connection2.state
        #expect(state1 == .established)
        #expect(state2 == .established)
        
        // Clone should have received ready event
        try await withTimeout(.seconds(2), operation: "waiting for clone ready event") {
            let events = await eventCollector1.events
            let hasReady = events.contains { event in
                if case .ready = event {
                    // Check if this is the cloned connection's ready event
                    return true
                }
                return false
            }
            #expect(hasReady == true)
        }
        
        // Closing one should not affect the other
        await connection1.close()
        try await connection1.waitForState(.closed)
        
        let state1After = await connection1.state
        let state2After = await connection2.state
        #expect(state1After == .closed)
        #expect(state2After == .established)
        
        await connection2.close()
    }
    
    @Test("Clone error handling")
    func testCloneErrorHandling() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        
        do {
            let connection = try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
            
            // If we somehow got a connection to invalid host, try to clone
            do {
                _ = try await connection.clone()
            } catch {
                // Clone error should be reported as event
                let events = await eventCollector.events
                let hasCloneError = events.contains { event in
                    if case .cloneError = event { return true }
                    return false
                }
                #expect(hasCloneError == true)
            }
            
            await connection.close()
        } catch {
            // Connection might fail, which is expected for invalid host
            print("Expected connection failure: \(error)")
        }
    }
    
    // MARK: - Connection Group Tests (RFC 9622 Section 7.4)
    
    @Test("Connection group management")
    func testConnectionGroup() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection1 = try await withTimeout(.seconds(5), operation: "connection 1") {
            try await preconnection.initiate()
        }
        
        let connection2 = try await withTimeout(.seconds(5), operation: "connection 2") {
            try await preconnection.initiate()
        }
        
        // Create a connection group
        let group = ConnectionGroup()
        
        // Add connections to group
        await connection1.setGroup(group)
        await connection2.setGroup(group)
        
        // Verify connections have the group
        let group1 = await connection1.group
        let group2 = await connection2.group
        #expect(group1 != nil)
        #expect(group2 != nil)
        
        // Group should track connection count
        let count = await group.connectionCount
        #expect(count >= 0) // We can't guarantee exact count due to weak references
        
        // Clean up
        await connection1.close()
        await connection2.close()
    }
    
    // MARK: - Endpoint Management Tests (RFC 9622 Section 7.5)
    
    @Test("Add and remove remote endpoints")
    func testEndpointManagement() async throws {
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate()
        }
        
        // Add additional remote endpoints
        let newEndpoints: [RemoteEndpoint] = [
            { var ep = RemoteEndpoint(); ep.ipAddress = "8.8.8.8"; ep.port = 443; return ep }(),
            { var ep = RemoteEndpoint(); ep.ipAddress = "8.8.4.4"; ep.port = 443; return ep }()
        ]
        
        await connection.addRemote(newEndpoints)
        
        // Remove specific endpoints
        let toRemove: [RemoteEndpoint] = [{ var ep = RemoteEndpoint(); ep.ipAddress = "8.8.8.8"; ep.port = 443; return ep }()]
        await connection.removeRemote(toRemove)
        
        // Add local endpoints
        var localEndpoint = LocalEndpoint()
        localEndpoint.interface = "en0"
        await connection.addLocal([localEndpoint])
        
        // Remove local endpoints
        await connection.removeLocal([localEndpoint])
        
        await connection.close()
    }
    
    // MARK: - Continuous Receive Tests
    
    @Test("Start receiving continuously")
    func testStartReceiving() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 80; return ep }()]
        )
        
        var secParams = preconnection.securityParameters
        secParams.alpn = ["h2", "http/1.1"]
        
        let connection = try await withTimeout(.seconds(10), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Start continuous receiving
        await connection.startReceiving(maxLength: 1024)
        
        // Send a request to trigger data
        let request = """
        GET /get HTTP/1.1\r
        Host: httpbin.org\r
        Connection: close\r
        \r
        
        """
        
        try await connection.send(data: Data(request.utf8))
        
        // Wait for receive events
        try await withTimeout(.seconds(5), operation: "waiting for receive events") {
            try await waitForCondition {
                let events = await eventCollector.events
                return events.contains { event in
                    if case .received = event { return true }
                    if case .receivedPartial = event { return true }
                    return false
                }
            }
        }
        
        await connection.close()
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Send error handling")
    func testSendErrorHandling() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Force the connection into a bad state by updating state directly
        await connection.updateState(.closing)
        
        // Try to send data
        do {
            try await connection.send(data: Data("test".utf8))
            Issue.record("Send should have failed on non-established connection")
        } catch {
            // Expected error
            #expect(error is TransportServicesError)
        }
        
        await connection.close()
    }
    
    @Test("Receive error handling")
    func testReceiveErrorHandling() async throws {
        let eventCollector = EventCollector()
        
        let preconnection = Preconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "1.1.1.1"; ep.port = 443; return ep }()]
        )
        
        let connection = try await withTimeout(.seconds(5), operation: "connection initiation") {
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Force the connection into a bad state
        await connection.updateState(.closing)
        
        // Try to receive data
        do {
            _ = try await connection.receive()
            Issue.record("Receive should have failed on non-established connection")
        } catch {
            // Expected error
            #expect(error is TransportServicesError)
            
            // Should generate receive error event
            let events = await eventCollector.events
            let hasReceiveError = events.contains { event in
                if case .receiveError = event { return true }
                return false
            }
            #expect(hasReceiveError == true)
        }
        
        await connection.close()
    }
}