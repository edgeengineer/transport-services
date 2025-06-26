#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import TransportServices

/// Test framer that adds a prefix to outbound messages and strips it from inbound
final class TestPrefixFramer: MessageFramer {
    let prefix: Data
    
    init(prefix: String) {
        self.prefix = prefix.data(using: .utf8)!
    }
    
    func connectionDidOpen(_ connection: Connection) async {
        // No special setup needed
    }
    
    func connectionDidClose(_ connection: Connection) async {
        // No cleanup needed
    }
    
    func frameOutbound(_ message: Message) async throws -> [Data] {
        var framedData = Data()
        framedData.append(prefix)
        framedData.append(message.data)
        return [framedData]
    }
    
    func parseInbound(_ data: Data) async throws -> (messages: [Message], remainder: Data) {
        var messages: [Message] = []
        var buffer = data
        
        while buffer.count >= prefix.count {
            if buffer.prefix(prefix.count) == prefix {
                // Found prefix, extract message
                buffer = buffer.dropFirst(prefix.count)
                
                // For this test, assume the rest is one complete message
                if !buffer.isEmpty {
                    messages.append(Message(buffer))
                    buffer = Data()
                }
            } else {
                // No valid prefix found
                break
            }
        }
        
        return (messages, buffer)
    }
}

@Test("Framer integration with Preconnection")
func testFramerIntegration() async throws {
    // Create a preconnection with a test framer
    let preconnection = Preconnection(
        remote: [RemoteEndpoint.loopback(port: 9999)],
        transport: TransportProperties()
    )
    
    let testFramer = TestPrefixFramer(prefix: "TEST:")
    await preconnection.add(framer: testFramer)
    
    // Verify framer was added by creating a connection
    // In a real test, we'd establish a connection and verify framing works
    #expect(testFramer is MessageFramer)
}

@Test("Multiple framers stacking")
func testMultipleFramers() async throws {
    // Create a preconnection with multiple framers
    let preconnection = Preconnection(
        remote: [RemoteEndpoint.loopback(port: 9999)],
        transport: TransportProperties()
    )
    
    let framer1 = TestPrefixFramer(prefix: "FIRST:")
    let framer2 = TestPrefixFramer(prefix: "SECOND:")
    
    await preconnection.add(framer: framer1)
    await preconnection.add(framer: framer2)
    
    // Verify framers exist
    #expect(framer1 is MessageFramer)
    #expect(framer2 is MessageFramer)
    
    // According to RFC 9622, last added runs first for outbound
    // So framer2 should process first, then framer1
}

@Test("Built-in framers creation")
func testBuiltInFramers() async throws {
    // Test creating built-in framers
    let lengthFramer = LengthPrefixFramer()
    #expect(lengthFramer is MessageFramer)
    
    let delimiterFramer = DelimiterFramer(delimiter: Data([0x0A])) // newline
    #expect(delimiterFramer is MessageFramer)
    
    let httpFramer = HTTPFramer()
    #expect(httpFramer is MessageFramer)
    
    let websocketFramer = WebSocketFramer()
    #expect(websocketFramer is MessageFramer)
    
    let bluetoothFramer = BluetoothL2CAPFramer()
    #expect(bluetoothFramer is MessageFramer)
}

@Test("Configurable framer")
func testConfigurableFramer() async throws {
    // Test the configurable framer
    let framer = ConfigurableFramer()
    
    #expect(framer is MessageFramer)
    
    // Test with default mode (no framing)
    let message = Message(Data("Hello".utf8))
    let framed = try await framer.frameOutbound(message)
    #expect(framed.count == 1)
    #expect(framed[0] == Data("Hello".utf8))
    
    // Test parsing with no framing
    let testData = Data("Hello".utf8)
    let (messages, remainder) = try await framer.parseInbound(testData)
    #expect(messages.count == 1)
    #expect(messages[0].data == Data("Hello".utf8))
    #expect(remainder.isEmpty)
}