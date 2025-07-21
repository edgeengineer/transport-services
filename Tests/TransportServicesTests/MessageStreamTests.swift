import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Message Stream Tests")
struct MessageStreamTests {
    
    @Test("Streaming messages with async iterator")
    func asyncMessageStream() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Server reads messages using async stream
        let readTask = Task {
            var messages: [String] = []
            for try await message in await serverConnection.incomingMessages {
                let text = String(data: message.data, encoding: .utf8) ?? ""
                messages.append(text)
                if messages.count >= 3 {
                    break
                }
            }
            return messages
        }
        
        // Client sends multiple messages
        for i in 1...3 {
            let message = Message(Data("Message \(i)".utf8))
            try await clientConnection.send(message)
            try await Task.sleep(for: .milliseconds(10))
        }
        
        // Verify messages received
        let receivedMessages = try await readTask.value
        #expect(receivedMessages.count == 3)
        #expect(receivedMessages[0] == "Message 1")
        #expect(receivedMessages[1] == "Message 2")
        #expect(receivedMessages[2] == "Message 3")
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Partial message sending with framing")
    func partialMessages() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Send a message in parts
        let part1 = Data("Hello, ".utf8)
        let part2 = Data("World!".utf8)
        
        var context = MessageContext()
        context.final = false
        
        try await clientConnection.sendPartial(part1, context: context, endOfMessage: false)
        
        context.final = true
        try await clientConnection.sendPartial(part2, context: context, endOfMessage: true)
        
        // With length-prefix framing, each sendPartial creates a separate message
        // Receive first message
        let received1 = try await TestUtils.withTimeout(seconds: 5) {
            try await serverConnection.receive()
        }
        let text1 = String(data: received1.data, encoding: .utf8) ?? ""
        #expect(text1 == "Hello, ")
        
        // Receive second message
        let received2 = try await TestUtils.withTimeout(seconds: 5) {
            try await serverConnection.receive()
        }
        let text2 = String(data: received2.data, encoding: .utf8) ?? ""
        #expect(text2 == "World!")
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("Message context properties")
    func messageContext() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Send messages with different priorities
        var highPriorityContext = MessageContext()
        highPriorityContext.priority = 255
        highPriorityContext.safelyReplayable = true
        
        let highPriorityMessage = Message(Data("High priority".utf8), context: highPriorityContext)
        try await clientConnection.send(highPriorityMessage)
        
        var lowPriorityContext = MessageContext()
        lowPriorityContext.priority = 1
        lowPriorityContext.final = true
        
        let lowPriorityMessage = Message(Data("Low priority".utf8), context: lowPriorityContext)
        try await clientConnection.send(lowPriorityMessage)
        
        // Receive messages
        let msg1 = try await TestUtils.withTimeout(seconds: 5) {
            try await serverConnection.receive()
        }
        let msg2 = try await TestUtils.withTimeout(seconds: 5) {
            try await serverConnection.receive()
        }
        
        // Verify messages received (order may vary based on implementation)
        let texts = [
            String(data: msg1.data, encoding: .utf8) ?? "",
            String(data: msg2.data, encoding: .utf8) ?? ""
        ]
        
        #expect(texts.contains("High priority"))
        #expect(texts.contains("Low priority"))
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
}
