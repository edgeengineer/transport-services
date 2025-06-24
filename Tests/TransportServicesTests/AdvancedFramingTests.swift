import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Advanced Framing Tests")
struct AdvancedFramingTests {
    
    @Test("Delimiter framing with line delimiters")
    func lineDelimitedFraming() async throws {
        let framer = DelimiterFramer.lineDelimited
        
        // Test framing outbound
        let message1 = Message(Data("Hello, World".utf8))
        let framed1 = try await framer.frameOutbound(message1)
        #expect(framed1.count == 1)
        #expect(framed1[0] == Data("Hello, World\n".utf8))
        
        // Test parsing inbound
        let input = Data("Line 1\nLine 2\nLine 3\n".utf8)
        let (messages, remainder) = try await framer.parseInbound(input)
        
        #expect(messages.count == 3)
        #expect(String(data: messages[0].data, encoding: .utf8) == "Line 1")
        #expect(String(data: messages[1].data, encoding: .utf8) == "Line 2")
        #expect(String(data: messages[2].data, encoding: .utf8) == "Line 3")
        #expect(remainder.isEmpty)
    }
    
    @Test("Delimiter framing with partial messages")
    func partialDelimiterFraming() async throws {
        let framer = DelimiterFramer.crlfDelimited
        
        // Send partial data
        let (messages1, _) = try await framer.parseInbound(Data("Hello".utf8))
        #expect(messages1.isEmpty) // No complete message yet
        
        // Complete the message
        let (messages2, _) = try await framer.parseInbound(Data(", World\r\n".utf8))
        #expect(messages2.count == 1)
        #expect(String(data: messages2[0].data, encoding: .utf8) == "Hello, World")
    }
    
    @Test("WebSocket framing")
    func webSocketFraming() async throws {
        let serverFramer = WebSocketFramer(mode: .server)
        let clientFramer = WebSocketFramer(mode: .client)
        
        // Client sends masked frame
        let clientMessage = Message(Data("Hello WebSocket".utf8))
        let clientFramed = try await clientFramer.frameOutbound(clientMessage)
        #expect(clientFramed.count == 1)
        
        // Server parses masked frame
        let (serverReceived, _) = try await serverFramer.parseInbound(clientFramed[0])
        #expect(serverReceived.count == 1)
        #expect(serverReceived[0].data == clientMessage.data)
        
        // Server sends unmasked frame
        let serverMessage = Message(Data("Response from server".utf8))
        let serverFramed = try await serverFramer.frameOutbound(serverMessage)
        
        // Client parses unmasked frame
        let (clientReceived, _) = try await clientFramer.parseInbound(serverFramed[0])
        #expect(clientReceived.count == 1)
        #expect(clientReceived[0].data == serverMessage.data)
    }
    
    @Test("Configurable framer mode switching")
    func configurableFramerModeSwitching() async throws {
        let framer = ConfigurableFramer()
        
        // Start with no framing
        let message1 = Message(Data("Raw data".utf8))
        let framed1 = try await framer.frameOutbound(message1)
        #expect(framed1 == [message1.data])
        
        // Switch to length-prefix mode
        await framer.setMode(.lengthPrefix(maxSize: 1024))
        let message2 = Message(Data("Length prefixed".utf8))
        let framed2 = try await framer.frameOutbound(message2)
        #expect(framed2.count == 1)
        #expect(framed2[0].count == 4 + message2.data.count) // 4 byte prefix + data
        
        // Parse length-prefixed data
        let (parsed, _) = try await framer.parseInbound(framed2[0])
        #expect(parsed.count == 1)
        #expect(parsed[0].data == message2.data)
        
        // Switch to delimiter mode
        await framer.setMode(.delimiter(Data("\n".utf8), includeDelimiter: false))
        let message3 = Message(Data("Line of text".utf8))
        let framed3 = try await framer.frameOutbound(message3)
        #expect(framed3 == [Data("Line of text\n".utf8)])
    }
    
    @Test("Fixed size framing")
    func fixedSizeFraming() async throws {
        let framer = ConfigurableFramer(mode: .fixedSize(16))
        
        // Exact size message
        let message1 = Message(Data("Exactly16 bytes!".utf8))
        let framed1 = try await framer.frameOutbound(message1)
        #expect(framed1 == [message1.data])
        
        // Wrong size should fail
        let message2 = Message(Data("Too short".utf8))
        do {
            _ = try await framer.frameOutbound(message2)
            Issue.record("Should have thrown error for wrong size")
        } catch {
            // Expected
        }
        
        // Parse fixed size messages
        let input = Data("First16BytesMsg!Second16ByteMsg!".utf8)
        let (messages, remainder) = try await framer.parseInbound(input)
        #expect(messages.count == 2)
        #expect(String(data: messages[0].data, encoding: .utf8) == "First16BytesMsg!")
        #expect(String(data: messages[1].data, encoding: .utf8) == "Second16ByteMsg!")
        #expect(remainder.isEmpty)
    }
    
    @Test("HTTP framing basic")
    func httpFramingBasic() async throws {
        let framer = HTTPFramer(mode: .server)
        
        // Simple GET request (no body)
        let request = Data("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".utf8)
        
        let (messages, _) = try await framer.parseInbound(request)
        #expect(messages.count == 1)
        // For no-body requests, the framer returns the complete headers
        #expect(messages[0].data == request)
        
        // Request with Content-Length - need to send headers first, then body
        let framer2 = HTTPFramer(mode: .server)
        let postHeaders = Data("POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Length: 13\r\n\r\n".utf8)
        let postBody = Data("Hello, World!".utf8)
        
        // Parse headers first
        let (messages2, _) = try await framer2.parseInbound(postHeaders)
        #expect(messages2.count == 0) // Waiting for body
        
        // Then parse body
        let (messages3, _) = try await framer2.parseInbound(postBody)
        #expect(messages3.count == 1)
        #expect(messages3[0].data == postBody)
    }
}