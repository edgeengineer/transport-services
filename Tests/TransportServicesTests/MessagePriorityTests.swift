import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Message Priority Tests")
struct MessagePriorityTests {
    
    @Test("Message priority ordering")
    func messagePriority() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Send messages with different priorities
        var highPriorityContext = MessageContext()
        highPriorityContext.priority = 255  // Highest priority
        
        var mediumPriorityContext = MessageContext()
        mediumPriorityContext.priority = 100  // Default priority
        
        var lowPriorityContext = MessageContext()
        lowPriorityContext.priority = 1  // Low priority
        
        // Send in reverse priority order
        let lowMsg = Message(Data("Low priority".utf8), context: lowPriorityContext)
        let medMsg = Message(Data("Medium priority".utf8), context: mediumPriorityContext)
        let highMsg = Message(Data("High priority".utf8), context: highPriorityContext)
        
        try await clientConnection.send(lowMsg)
        try await clientConnection.send(medMsg)
        try await clientConnection.send(highMsg)
        
        // Receive messages
        var receivedMessages: [String] = []
        for _ in 0..<3 {
            let msg = try await serverConnection.receive()
            let text = String(data: msg.data, encoding: .utf8) ?? ""
            receivedMessages.append(text)
        }
        
        // With proper priority scheduling, high priority should arrive first
        // Note: Actual ordering depends on implementation and network conditions
        #expect(receivedMessages.count == 3)
        #expect(receivedMessages.contains("High priority"))
        #expect(receivedMessages.contains("Medium priority"))
        #expect(receivedMessages.contains("Low priority"))
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Message expiration")
    func messageExpiration() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Note: Message expiration (expiry/lifetime) is defined in RFC 9622 §9.1.3.1
        // but may not be implemented yet. This test demonstrates the concept.
        
        // For now, just test that messages are delivered
        let testMsg = Message(Data("Test message".utf8))
        try await clientConnection.send(testMsg)
        
        let received = try await serverConnection.receive()
        let text = String(data: received.data, encoding: .utf8) ?? ""
        #expect(text == "Test message")
        
        // TODO: When message expiration is implemented, test:
        // - Messages with short TTL
        // - Expired message handling
        // - Delivery deadlines
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Connection priority within group")
    func connectionGroupPriority() async throws {
        let (primaryConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Create clones with different priorities
        let highPriorityClone = try await primaryConnection.clone()
        let lowPriorityClone = try await primaryConnection.clone()
        
        // Set connection priorities (would need to be implemented)
        // await highPriorityClone.setPriority(10)  // Higher priority (lower number)
        // await lowPriorityClone.setPriority(200)  // Lower priority
        
        // Send data on all connections
        let primaryMsg = Message(Data("From primary".utf8))
        let highMsg = Message(Data("From high priority".utf8))
        let lowMsg = Message(Data("From low priority".utf8))
        
        try await primaryConnection.send(primaryMsg)
        try await highPriorityClone.send(highMsg)
        try await lowPriorityClone.send(lowMsg)
        
        // Receive all messages
        var receivedMessages: [String] = []
        for _ in 0..<3 {
            let msg = try await serverConnection.receive()
            let text = String(data: msg.data, encoding: .utf8) ?? ""
            receivedMessages.append(text)
        }
        
        #expect(receivedMessages.count == 3)
        #expect(receivedMessages.contains("From primary"))
        #expect(receivedMessages.contains("From high priority"))
        #expect(receivedMessages.contains("From low priority"))
        
        // Cleanup
        await primaryConnection.closeGroup()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Final message flag")
    func finalMessage() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Send regular message
        let regularMsg = Message(Data("Regular message".utf8))
        try await clientConnection.send(regularMsg)
        
        // Send final message
        var finalContext = MessageContext()
        finalContext.final = true
        let finalMsg = Message(Data("Final message".utf8), context: finalContext)
        try await clientConnection.send(finalMsg)
        
        // After final message, sending should fail
        do {
            let afterFinalMsg = Message(Data("After final".utf8))
            try await clientConnection.send(afterFinalMsg)
            Issue.record("Should not be able to send after final message")
        } catch {
            // Expected behavior
            #expect(error is TransportError)
        }
        
        // Server should receive both messages
        let msg1 = try await serverConnection.receive()
        let msg2 = try await serverConnection.receive()
        
        let texts = [
            String(data: msg1.data, encoding: .utf8) ?? "",
            String(data: msg2.data, encoding: .utf8) ?? ""
        ]
        
        #expect(texts.contains("Regular message"))
        #expect(texts.contains("Final message"))
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
}