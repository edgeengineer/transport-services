#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A framer for WebSocket protocol (RFC 6455).
///
/// This framer handles WebSocket frame encoding/decoding including:
/// - Frame headers with opcode, mask, and length
/// - Masking/unmasking for client messages
/// - Support for continuation frames
public struct WebSocketFramer: MessageFramer, Sendable {
    
    /// WebSocket opcodes
    public enum Opcode: UInt8 {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }
    
    /// Client or server mode (affects masking)
    public enum Mode: Sendable {
        case client  // Must mask outgoing frames
        case server  // Must not mask outgoing frames
    }
    
    private let mode: Mode
    private let maxFrameSize: Int
    
    /// Parsing state
    private final class ParsingState: @unchecked Sendable {
        var buffer = Data()
        var continuationBuffer = Data()
        var expectingContinuation = false
    }
    
    private let state = ParsingState()
    
    /// Creates a new WebSocket framer
    public init(mode: Mode = .server, maxFrameSize: Int = 16 * 1024 * 1024) {
        self.mode = mode
        self.maxFrameSize = maxFrameSize
    }
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        var frame = Data()
        
        // FIN = 1, RSV = 0, Opcode = binary (0x2)
        frame.append(0x80 | Opcode.binary.rawValue)
        
        let messageLength = message.data.count
        let shouldMask = (mode == .client)
        
        // Payload length and mask bit
        if messageLength < 126 {
            frame.append(UInt8(messageLength) | (shouldMask ? 0x80 : 0x00))
        } else if messageLength < 65536 {
            frame.append(126 | (shouldMask ? 0x80 : 0x00))
            frame.append(UInt8((messageLength >> 8) & 0xFF))
            frame.append(UInt8(messageLength & 0xFF))
        } else {
            frame.append(127 | (shouldMask ? 0x80 : 0x00))
            // Write 8 bytes for length (big-endian)
            for i in (0..<8).reversed() {
                frame.append(UInt8((messageLength >> (i * 8)) & 0xFF))
            }
        }
        
        if shouldMask {
            // Generate random mask
            let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
            frame.append(contentsOf: mask)
            
            // Mask the payload
            var maskedData = Data()
            for (index, byte) in message.data.enumerated() {
                maskedData.append(byte ^ mask[index % 4])
            }
            frame.append(maskedData)
        } else {
            // No masking for server
            frame.append(message.data)
        }
        
        return [frame]
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        var messages: [Message] = []
        
        state.buffer.append(bytes)
        
        while state.buffer.count >= 2 {
            let firstByte = state.buffer[0]
            let secondByte = state.buffer[1]
            
            let fin = (firstByte & 0x80) != 0
            let opcode = Opcode(rawValue: firstByte & 0x0F)
            let masked = (secondByte & 0x80) != 0
            var payloadLength = Int(secondByte & 0x7F)
            
            var headerSize = 2
            
            // Extended payload length
            if payloadLength == 126 {
                guard state.buffer.count >= 4 else { break }
                payloadLength = Int(state.buffer[2]) << 8 | Int(state.buffer[3])
                headerSize = 4
            } else if payloadLength == 127 {
                guard state.buffer.count >= 10 else { break }
                payloadLength = 0
                for i in 2..<10 {
                    payloadLength = (payloadLength << 8) | Int(state.buffer[i])
                }
                headerSize = 10
            }
            
            // Mask key
            var maskKey: [UInt8]?
            if masked {
                guard state.buffer.count >= headerSize + 4 else { break }
                maskKey = Array(state.buffer[headerSize..<headerSize + 4])
                headerSize += 4
            }
            
            // Check if we have complete frame
            let totalSize = headerSize + payloadLength
            guard state.buffer.count >= totalSize else { break }
            
            // Extract payload
            var payload = Data(state.buffer[headerSize..<totalSize])
            
            // Unmask if needed
            if let mask = maskKey {
                for i in 0..<payload.count {
                    payload[i] ^= mask[i % 4]
                }
            }
            
            // Handle frame based on opcode
            switch opcode {
            case .text, .binary:
                if fin {
                    messages.append(Message(payload))
                } else {
                    state.continuationBuffer = payload
                    state.expectingContinuation = true
                }
                
            case .continuation:
                state.continuationBuffer.append(payload)
                if fin {
                    messages.append(Message(state.continuationBuffer))
                    state.continuationBuffer = Data()
                    state.expectingContinuation = false
                }
                
            case .close, .ping, .pong:
                // Control frames - could be handled specially
                messages.append(Message(payload))
                
            default:
                throw TransportError.receiveFailure("Unknown WebSocket opcode: \(firstByte & 0x0F)")
            }
            
            // Remove processed frame
            state.buffer = Data(state.buffer.dropFirst(totalSize))
        }
        
        return (messages, Data())
    }
}