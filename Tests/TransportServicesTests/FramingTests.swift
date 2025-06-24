import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Message Framing Tests")
struct FramingTests {
    
    @Test("Length-prefix framing for multiple messages")
    func lengthPrefixFraming() async throws {
        let (client, server, listener) = try await TestUtils.createClientServerPair()
        
        // Send multiple messages rapidly
        let messages = [
            "First message",
            "Second",
            "A much longer third message with more content",
            "4",
            "Fifth and final message"
        ]
        
        // Send all messages
        for message in messages {
            let data = Data(message.utf8)
            try await client.send(Message(data))
        }
        
        // Receive all messages
        var received: [String] = []
        for _ in messages {
            let message = try await server.receive()
            let text = String(data: message.data, encoding: .utf8) ?? ""
            received.append(text)
        }
        
        // Verify all messages were received correctly
        #expect(received == messages)
        
        // Cleanup
        await client.close()
        await server.close()
        await listener.stop()
    }
    
    @Test("Large message framing")
    func largeMessageFraming() async throws {
        let (client, server, listener) = try await TestUtils.createClientServerPair()
        
        // Create a large message (500KB)
        let largeData = Data(repeating: 65, count: 500_000) // 'A' repeated
        let message = Message(largeData)
        
        // Send large message
        try await client.send(message)
        
        // Receive large message
        let received = try await server.receive()
        
        // Verify size and content
        #expect(received.data.count == largeData.count)
        #expect(received.data == largeData)
        
        // Cleanup
        await client.close()
        await server.close()
        await listener.stop()
    }
    
    @Test("Interleaved message sending")
    func interleavedMessages() async throws {
        let (client, server, listener) = try await TestUtils.createClientServerPair()
        
        // Both sides send messages
        let clientMessages = ["Client 1", "Client 2", "Client 3"]
        let serverMessages = ["Server A", "Server B", "Server C"]
        
        // Send from both sides concurrently
        let clientSendTask = Task {
            for msg in clientMessages {
                try await client.send(Message(Data(msg.utf8)))
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        
        let serverSendTask = Task {
            for msg in serverMessages {
                try await server.send(Message(Data(msg.utf8)))
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        
        // Receive on both sides
        var clientReceived: [String] = []
        var serverReceived: [String] = []
        
        let clientReceiveTask = Task {
            for _ in serverMessages {
                let msg = try await client.receive()
                clientReceived.append(String(data: msg.data, encoding: .utf8) ?? "")
            }
        }
        
        let serverReceiveTask = Task {
            for _ in clientMessages {
                let msg = try await server.receive()
                serverReceived.append(String(data: msg.data, encoding: .utf8) ?? "")
            }
        }
        
        // Wait for all tasks
        try await clientSendTask.value
        try await serverSendTask.value
        try await clientReceiveTask.value
        try await serverReceiveTask.value
        
        // Verify messages
        #expect(clientReceived == serverMessages)
        #expect(serverReceived == clientMessages)
        
        // Cleanup
        await client.close()
        await server.close()
        await listener.stop()
    }
    
    @Test("Message boundary preservation")
    func messageBoundaryPreservation() async throws {
        let (client, server, listener) = try await TestUtils.createClientServerPair()
        
        // Send messages with similar prefixes to test boundary preservation
        let messages = [
            "Hello",
            "Hello, World",
            "Hello, World!",
            "Hell",
            "He"
        ]
        
        // Send all at once
        for msg in messages {
            try await client.send(Message(Data(msg.utf8)))
        }
        
        // Receive and verify each maintains its boundary
        var received: [String] = []
        for _ in messages {
            let msg = try await server.receive()
            received.append(String(data: msg.data, encoding: .utf8) ?? "")
        }
        
        #expect(received == messages)
        
        // Cleanup
        await client.close()
        await server.close()
        await listener.stop()
    }
}