import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Message Tests")
struct MessageTests {
    
    @Test("Message creation with data")
    func messageCreation() {
        let data = Data("Hello, World!".utf8)
        let message = Message(data)
        
        #expect(message.data == data)
        #expect(message.context.priority == 100)
        #expect(message.context.safelyReplayable == false)
        #expect(message.context.final == false)
    }
    
    @Test("Message with custom context")
    func messageWithContext() {
        let data = Data("Test message".utf8)
        var context = MessageContext()
        context.priority = 200
        context.safelyReplayable = true
        context.final = true
        
        let message = Message(data, context: context)
        
        #expect(message.data == data)
        #expect(message.context.priority == 200)
        #expect(message.context.safelyReplayable == true)
        #expect(message.context.final == true)
    }
    
    @Test("Empty message")
    func emptyMessage() {
        let message = Message(Data())
        
        #expect(message.data.isEmpty)
        #expect(message.context.priority == 100)
    }
    
    @Test("Large message")
    func largeMessage() {
        // Create a 1MB message
        let size = 1024 * 1024
        let data = Data(repeating: 0x42, count: size)
        let message = Message(data)
        
        #expect(message.data.count == size)
        #expect(message.data.first == 0x42)
    }
    
    @Test("Message context properties")
    func messageContextProperties() {
        var context = MessageContext()
        
        // Test priority boundaries
        context.priority = 0
        #expect(context.priority == 0)
        
        context.priority = 255
        #expect(context.priority == 255)
        
        context.priority = 150
        #expect(context.priority == 150)
        
        // Test boolean properties
        context.safelyReplayable = true
        #expect(context.safelyReplayable == true)
        
        context.final = true
        #expect(context.final == true)
    }
}