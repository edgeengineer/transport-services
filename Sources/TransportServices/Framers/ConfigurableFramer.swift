#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A configurable framer that allows switching between different framing modes.
///
/// This framer can be configured to use different framing strategies, making it
/// suitable for protocols that negotiate framing during connection establishment.
public actor ConfigurableFramer: MessageFramer {
    
    /// Available framing modes
    public enum FramingMode: Sendable {
        case lengthPrefix(maxSize: Int)
        case delimiter(Data, includeDelimiter: Bool)
        case fixedSize(Int)
        case noFraming
    }
    
    private var mode: FramingMode
    private var buffer = Data()
    
    /// Creates a new configurable framer
    public init(mode: FramingMode = .noFraming) {
        self.mode = mode
    }
    
    /// Changes the framing mode
    public func setMode(_ newMode: FramingMode) {
        mode = newMode
        // Clear buffer when changing modes
        buffer = Data()
    }
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        let currentMode = mode
        
        switch currentMode {
        case .lengthPrefix(let maxSize):
            guard message.data.count <= maxSize else {
                throw TransportError.sendFailure("Message too large")
            }
            var frame = Data()
            let length = UInt32(message.data.count)
            frame.append(UInt8((length >> 24) & 0xFF))
            frame.append(UInt8((length >> 16) & 0xFF))
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
            frame.append(message.data)
            return [frame]
            
        case .delimiter(let delimiter, _):
            if message.data.contains(delimiter) {
                throw TransportError.sendFailure("Message contains delimiter")
            }
            var frame = message.data
            frame.append(delimiter)
            return [frame]
            
        case .fixedSize(let size):
            guard message.data.count == size else {
                throw TransportError.sendFailure("Message size must be exactly \(size) bytes")
            }
            return [message.data]
            
        case .noFraming:
            return [message.data]
        }
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        
        buffer.append(bytes)
        var messages: [Message] = []
        
        switch mode {
        case .lengthPrefix(let maxSize):
            while buffer.count >= 4 {
                let length = UInt32(buffer[0]) << 24 |
                            UInt32(buffer[1]) << 16 |
                            UInt32(buffer[2]) << 8 |
                            UInt32(buffer[3])
                
                guard length <= maxSize else {
                    throw TransportError.receiveFailure("Message too large")
                }
                
                let totalSize = 4 + Int(length)
                guard buffer.count >= totalSize else { break }
                
                let messageData = buffer[4..<totalSize]
                messages.append(Message(Data(messageData)))
                buffer = Data(buffer.dropFirst(totalSize))
            }
            
        case .delimiter(let delimiter, let includeDelimiter):
            while let range = buffer.range(of: delimiter) {
                let messageData: Data
                if includeDelimiter {
                    let endIndex = buffer.index(range.lowerBound, offsetBy: delimiter.count)
                    messageData = buffer[..<endIndex]
                } else {
                    messageData = buffer[..<range.lowerBound]
                }
                
                messages.append(Message(messageData))
                let dropCount = range.upperBound - buffer.startIndex
                buffer = Data(buffer.dropFirst(dropCount))
            }
            
        case .fixedSize(let size):
            while buffer.count >= size {
                let messageData = buffer[..<size]
                messages.append(Message(Data(messageData)))
                buffer = Data(buffer.dropFirst(size))
            }
            
        case .noFraming:
            if !buffer.isEmpty {
                messages.append(Message(buffer))
                buffer = Data()
            }
        }
        
        return (messages, Data())
    }
}