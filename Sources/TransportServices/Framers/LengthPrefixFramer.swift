#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A simple length-prefix message framer.
///
/// This framer prefixes each message with a 4-byte big-endian length field.
/// It's suitable for binary protocols that need reliable message boundaries.
public struct LengthPrefixFramer: MessageFramer, Sendable {
    
    /// Internal state for parsing
    private final class ParsingState: @unchecked Sendable {
        var buffer = Data()
    }
    
    private let state = ParsingState()
    private let maxMessageSize: UInt32
    
    /// Creates a new length-prefix framer.
    /// - Parameter maxMessageSize: Maximum allowed message size (default: 1MB)
    public init(maxMessageSize: UInt32 = 1024 * 1024) {
        self.maxMessageSize = maxMessageSize
    }
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        let length = UInt32(message.data.count)
        
        guard length <= maxMessageSize else {
            throw TransportError.sendFailure("Message too large: \(length) bytes (max: \(maxMessageSize))")
        }
        
        var frame = Data()
        
        // Write 4-byte length in big-endian
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        
        // Append message data
        frame.append(message.data)
        
        return [frame]
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        var messages: [Message] = []
        
        // Add new bytes to buffer
        state.buffer.append(bytes)
        
        // Parse complete messages
        while state.buffer.count >= 4 {
            // Read length prefix (big-endian)
            let length = UInt32(state.buffer[0]) << 24 |
                        UInt32(state.buffer[1]) << 16 |
                        UInt32(state.buffer[2]) << 8 |
                        UInt32(state.buffer[3])
            
            guard length <= maxMessageSize else {
                throw TransportError.receiveFailure("Message too large: \(length) bytes (max: \(maxMessageSize))")
            }
            
            // Check if we have the complete message
            let totalSize = 4 + Int(length)
            guard state.buffer.count >= totalSize else {
                // Not enough data yet
                break
            }
            
            // Extract message data
            let messageData = state.buffer[4..<totalSize]
            messages.append(Message(messageData))
            
            // Remove processed data from buffer
            state.buffer = state.buffer.dropFirst(totalSize)
        }
        
        // Return empty remainder since we maintain state internally
        return (messages, Data())
    }
}