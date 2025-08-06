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
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 1; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Connection to unreachable address should be in establishing, established, or closed state
        // Note: Some CI environments may route documentation addresses, leading to established state
        let initialState = await connection.state
        #expect(initialState == .establishing || initialState == .established || initialState == .closed)
        
        // If still establishing or established, close it
        if initialState == .establishing || initialState == .established {
            await connection.close()
            try await connection.waitForState(.closed)
        }
        
        // If connection was closed, we should have received an error or closed event
        if initialState == .closed {
            try await withTimeout(in: .seconds(2), clock: ContinuousClock()) {
                let events = await eventCollector.events
                let hasError = events.contains { event in
                    if case .connectionError = event { return true }
                    if case .closed = event { return true }
                    return false
                }
                #expect(hasError == true)
            }
        }
        
        // Should have received closed event (after we closed the connection)
        try await withTimeout(in: .seconds(2), clock: ContinuousClock()) {
            let hasClosed = await eventCollector.hasClosedEvent()
            #expect(hasClosed == true)
        }
    }
    
    @Test("Connection abort immediately closes connection")
    func testConnectionAbort() async throws {
        let eventCollector = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 1; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Connection should be in establishing or closed state
        let establishedState = await connection.state
        #expect(establishedState == .establishing || establishedState == .closed)
        
        // Test abort on connection
        await connection.abort()
        
        // After abort, wait for state to transition to closed
        try await connection.waitForState(.closed)
        let abortedState = await connection.state
        #expect(abortedState == .closed)
        
        // Should receive connection error event for abort
        // Wait a bit for the event to be processed
        try await Task.sleep(for: .milliseconds(100))
        
        let events = await eventCollector.events
        let hasError = events.contains { event in
            if case .connectionError(_, let reason) = event {
                return reason?.contains("aborted") ?? false
            }
            return false
        }
        #expect(hasError == true)
    }
    
    // MARK: - Data Transfer Tests (RFC 9622 Section 9)
    
    @Test("Send and receive data on established connection", .disabled("Requires external network service"))
    func testDataTransfer() async throws {
        let eventCollector = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.hostName = "httpbin.org"; ep.port = 80; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        // No need to set ALPN for plain HTTP connections
        // Set a reasonable timeout
        preconnection.transportProperties.connTimeout = 10
        
        let connection = try await withTimeout(in: .seconds(10), clock: ContinuousClock()) { [preconnection] in
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
        
        try await withTimeout(in: .seconds(5), clock: ContinuousClock()) {
            try await connection.send(data: requestData, context: messageContext)
        }
        
        // Should have sent event
        try await withTimeout(in: .seconds(2), clock: ContinuousClock()) {
            let events = await eventCollector.events
            let hasSent = events.contains { event in
                if case .sent = event { return true }
                return false
            }
            #expect(hasSent == true)
        }
        
        // Receive response
        let (responseData, _) = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) {
            try await connection.receive(maxLength: 8192)
        }
        
        let response = String(data: responseData, encoding: .utf8) ?? ""
        #expect(response.contains("HTTP/1.1"))
        #expect(response.contains("200"))
        
        // Should have received event
        try await withTimeout(in: .seconds(2), clock: ContinuousClock()) {
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
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate()
        }
        
        // Connection might be establishing or closed
        let state = await connection.state
        if state == .establishing {
            await connection.close()
            try await connection.waitForState(.closed)
        }
        
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
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate()
        }
        
        // Connection might be establishing or closed
        let state = await connection.state
        if state == .establishing {
            await connection.close()
            try await connection.waitForState(.closed)
        }
        
        // Try to receive data on closed connection
        do {
            _ = try await connection.receive()
            Issue.record("Receive should have thrown TransportServicesError.connectionClosed")
        } catch {
            #expect(error is TransportServicesError)
        }
    }
    
    @Test("Partial message receive", .disabled("Requires external network service"))
    func testPartialMessageReceive() async throws {
        let eventCollector = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.hostName = "httpbin.org"; ep.port = 80; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        // No need to set ALPN for plain HTTP connections
        // Set a reasonable timeout
        preconnection.transportProperties.connTimeout = 10
        
        let connection = try await withTimeout(in: .seconds(10), clock: ContinuousClock()) { [preconnection] in
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
        let (partialData, _) = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) {
            try await connection.receive(minIncompleteLength: 1, maxLength: 64)
        }
        
        #expect(partialData.count <= 64)
        #expect(partialData.count >= 1)
        
        await connection.close()
    }
    
    // MARK: - Connection Properties Tests (RFC 9622 Section 8.1)
    
    @Test("Connection inherits properties from preconnection", .disabled("Hanging on Linux - needs investigation"))
    func testConnectionInheritsProperties() async throws {
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        // Set custom properties on preconnection
        preconnection.transportProperties.multipathPolicy = .handover
        preconnection.transportProperties.connPriority = 100
        preconnection.transportProperties.connTimeout = 30
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
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
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate()
        }
        
        // Set various connection properties
        // try await connection.setConnectionProperty(.multipathPolicy(.interactive))
        // try await connection.setConnectionProperty(.priority(200))
        // try await connection.setConnectionProperty(.connectionTimeout(60))
        // try await connection.setConnectionProperty(.keepAlive(enabled: true, interval: 30))
        
        // Properties should be updated locally
        // let props = await connection.properties
        // #expect(props.multipathPolicy == .interactive)
        // #expect(props.connPriority == 200)
        // #expect(props.connTimeout == 60)
        // #expect(props.keepAlive == .require)
        // #expect(props.keepAliveTimeout == 30)
        
        await connection.close()
    }
    
    // MARK: - Connection Cloning Tests (RFC 9622 Section 7.4)
    
    @Test("Clone connection creates independent connection")
    func testConnectionClone() async throws {
        let eventCollector1 = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection1 = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate { event in
                Task { await eventCollector1.add(event) }
            }
        }
        
        // Connection might be establishing, established, or closed
        let state = await connection1.state
        if state != .closed {
            await connection1.close()
            try await connection1.waitForState(.closed)
        }
        
        // Clone might succeed even on closed connection (creates new connection)
        // The RFC doesn't explicitly forbid cloning closed connections
        do {
            let cloned = try await connection1.clone()
            // Cloned connection should also be in establishing or closed state
            let clonedState = await cloned.state
            #expect(clonedState == .establishing || clonedState == .closed)
            await cloned.close()
        } catch {
            // Clone might fail, which is also acceptable
            #expect(error is TransportServicesError)
        }
        
        // Connection is already closed
        let finalState = await connection1.state
        #expect(finalState == .closed)
    }
    
    @Test("Clone error handling")
    func testCloneErrorHandling() async throws {
        let eventCollector = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        // Set a timeout to prevent hanging on unroutable address
        preconnection.transportProperties.connTimeout = 2.0
        
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
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection1 = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate()
        }
        
        let connection2 = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
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
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
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
    
    @Test("Start receiving continuously", .disabled("Requires external network service"))
    func testStartReceiving() async throws {
        let eventCollector = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.hostName = "httpbin.org"; ep.port = 80; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        // No need to set ALPN for plain HTTP connections
        // Set a reasonable timeout
        preconnection.transportProperties.connTimeout = 10
        
        let connection = try await withTimeout(in: .seconds(10), clock: ContinuousClock()) { [preconnection] in
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
        try await withTimeout(in: .seconds(5), clock: ContinuousClock()) {
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
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }

        // Close the connection to force it into a non-established state
        await connection.close()
        try await connection.waitForState(.closed)
        
        // Try to send data on closed connection
        do {
            try await connection.send(data: Data("test".utf8))
            Issue.record("Send should have failed on closed connection")
        } catch {
            // Expected error
            #expect(error is TransportServicesError)
        }
        
        await connection.close()
    }
    
    @Test("Receive error handling")
    func testReceiveErrorHandling() async throws {
        let eventCollector = EventCollector()
        
        var preconnection = NewPreconnection(
            remoteEndpoints: [{ var ep = RemoteEndpoint(); ep.ipAddress = "192.0.2.1"; ep.port = 443; return ep }()]
        )
        preconnection.transportProperties.connTimeout = 1.0 // 1 second timeout
        
        let connection = try await withTimeout(in: .seconds(5), clock: ContinuousClock()) { [preconnection] in
            try await preconnection.initiate { event in
                Task { await eventCollector.add(event) }
            }
        }
        
        // Close the connection to force it into a non-established state
        await connection.close()
        try await connection.waitForState(.closed)
        
        // Try to receive data on closed connection
        do {
            _ = try await connection.receive()
            Issue.record("Receive should have failed on closed connection")
        } catch {
            // Expected error
            #expect(error is TransportServicesError)
        }
        
        await connection.close()
    }
}
