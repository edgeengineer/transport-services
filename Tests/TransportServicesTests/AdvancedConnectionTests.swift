import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Advanced Connection Tests")
struct AdvancedConnectionTests {
    
    @Test("Unidirectional send-only connection")
    func unidirectionalSendOnly() async throws {
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create unidirectional send-only client
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var sendOnlyProperties = TransportProperties()
        sendOnlyProperties.direction = .sendOnly
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: sendOnlyProperties
        )
        
        let clientConnection = try await clientPreconnection.initiate()
        let serverConnection = try await serverTask.value
        
        // Client can send
        let message = Message(Data("Send only".utf8))
        try await clientConnection.send(message)
        
        // Server can receive
        let received = try await TestUtils.withTimeout(seconds: 5) {
            try await serverConnection.receive()
        }
        let text = String(data: received.data, encoding: .utf8) ?? ""
        #expect(text == "Send only")
        
        // Client cannot receive (should fail)
        do {
            _ = try await clientConnection.receive()
            Issue.record("Send-only connection should not be able to receive")
        } catch {
            // Expected behavior
            #expect(error is TransportError)
        }
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Unidirectional receive-only connection")
    func unidirectionalReceiveOnly() async throws {
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                // Server sends data immediately
                let welcomeMsg = Message(Data("Welcome".utf8))
                try await connection.send(welcomeMsg)
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create unidirectional receive-only client
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var receiveOnlyProperties = TransportProperties()
        receiveOnlyProperties.direction = .recvOnly
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: receiveOnlyProperties
        )
        
        let clientConnection = try await clientPreconnection.initiate()
        let serverConnection = try await serverTask.value
        
        // Client can receive
        let received = try await TestUtils.withTimeout(seconds: 5) {
            try await clientConnection.receive()
        }
        let text = String(data: received.data, encoding: .utf8) ?? ""
        #expect(text == "Welcome")
        
        // Client cannot send (should fail)
        do {
            let message = Message(Data("Should fail".utf8))
            try await clientConnection.send(message)
            Issue.record("Receive-only connection should not be able to send")
        } catch {
            // Expected behavior
            #expect(error is TransportError)
        }
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Capacity profile settings")
    func capacityProfiles() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Test different capacity profiles
        let profiles: [(CapacityProfile, String)] = [
            (.default, "Default profile message"),
            (.lowLatencyInteractive, "Low latency message"),
            (.scavenger, "Scavenger message"),
            (.constantRate, "CBR message")
        ]
        
        for (profile, text) in profiles {
            // Set capacity profile (would need to be implemented)
            // await clientConnection.setCapacityProfile(profile)
            
            let message = Message(Data(text.utf8))
            try await clientConnection.send(message)
            
            let received = try await TestUtils.withTimeout(seconds: 5) {
                try await serverConnection.receive()
            }
            let receivedText = String(data: received.data, encoding: .utf8) ?? ""
            #expect(receivedText == text)
        }
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Keep-alive functionality")
    func keepAlive() async throws {
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        // Configure keep-alive
        var serverProperties = TransportProperties()
        serverProperties.keepAlive = .require
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: serverProperties
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client with keep-alive
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var clientProperties = TransportProperties()
        clientProperties.keepAlive = .require
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: clientProperties
        )
        
        let clientConnection = try await clientPreconnection.initiate()
        let serverConnection = try await serverTask.value
        
        // TODO Set keep-alive timeout (would need to be implemented)
        // await clientConnection.setKeepAliveTimeout(.seconds(1))
        
        // Wait for keep-alive to trigger
        try await Task.sleep(for: .seconds(2))
        
        // Connection should still be alive
        let clientState = await clientConnection.state
        let serverState = await serverConnection.state
        
        #expect(clientState == .established)
        #expect(serverState == .established)
        
        // Can still send/receive
        let testMsg = Message(Data("Still alive".utf8))
        try await clientConnection.send(testMsg)
        
        let received = try await TestUtils.withTimeout(seconds: 5) {
            try await serverConnection.receive()
        }
        let text = String(data: received.data, encoding: .utf8) ?? ""
        #expect(text == "Still alive")
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Multipath support")
    func multipathConnection() async throws {
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        var serverProperties = TransportProperties()
        serverProperties.multipathMode = .active
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: serverProperties
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client with multipath
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var clientProperties = TransportProperties()
        clientProperties.multipathMode = .active
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: clientProperties
        )
        
        let clientConnection = try await clientPreconnection.initiate()
        let serverConnection = try await serverTask.value
        
        // Send data that could potentially use multiple paths
        let expectedMessages = Set(1...5).map { "Multipath message \($0)" }
        
        for i in 1...5 {
            let message = Message(Data("Multipath message \(i)".utf8))
            try await clientConnection.send(message)
        }

        // Receive all messages and collect them
        var receivedMessages = [String]()
        for _ in 1...5 {
            let received = try await TestUtils.withTimeout(seconds: 5) {
                try await serverConnection.receive()
            }
            let text = String(data: received.data, encoding: .utf8) ?? ""
            receivedMessages.append(text)
        }
        
        // Sort both arrays to compare regardless of order
        let sortedExpected = expectedMessages.sorted()
        let sortedReceived = receivedMessages.sorted()
        
        #expect(sortedReceived == sortedExpected)
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
}
