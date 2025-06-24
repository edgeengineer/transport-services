#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A framer that uses delimiters to separate messages.
///
/// This framer is suitable for text-based protocols like HTTP, SMTP, or custom
/// line-oriented protocols. It scans for delimiter sequences and treats data
/// between delimiters as complete messages.
public struct DelimiterFramer: MessageFramer, Sendable {
    
    /// The delimiter sequence
    private let delimiter: Data
    
    /// Maximum allowed message size
    private let maxMessageSize: Int
    
    /// Whether to include the delimiter in the message
    private let includeDelimiter: Bool
    
    /// Internal parsing state
    private final class ParsingState: @unchecked Sendable {
        var buffer = Data()
    }
    
    private let state = ParsingState()
    
    /// Creates a new delimiter-based framer.
    /// - Parameters:
    ///   - delimiter: The delimiter sequence (e.g., "\r\n" for CRLF)
    ///   - maxMessageSize: Maximum allowed message size (default: 64KB)
    ///   - includeDelimiter: Whether to include delimiter in messages (default: false)
    public init(delimiter: Data, 
                maxMessageSize: Int = 65536,
                includeDelimiter: Bool = false) {
        self.delimiter = delimiter
        self.maxMessageSize = maxMessageSize
        self.includeDelimiter = includeDelimiter
    }
    
    /// Convenience initializer for string delimiters
    public init(delimiter: String,
                maxMessageSize: Int = 65536,
                includeDelimiter: Bool = false) {
        self.init(delimiter: Data(delimiter.utf8),
                  maxMessageSize: maxMessageSize,
                  includeDelimiter: includeDelimiter)
    }
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        guard message.data.count <= maxMessageSize else {
            throw TransportError.sendFailure("Message too large: \(message.data.count) bytes")
        }
        
        // Check if message already contains delimiter
        if message.data.contains(delimiter) && !includeDelimiter {
            throw TransportError.sendFailure("Message contains delimiter")
        }
        
        // Append delimiter to message
        var framedData = message.data
        framedData.append(delimiter)
        
        return [framedData]
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        var messages: [Message] = []
        
        // Add new data to buffer
        state.buffer.append(bytes)
        
        // Check if buffer is getting too large
        if state.buffer.count > maxMessageSize + delimiter.count {
            throw TransportError.receiveFailure("Buffer overflow: no delimiter found")
        }
        
        // Search for delimiters
        while true {
            guard let range = state.buffer.range(of: delimiter) else {
                // No delimiter found, keep buffering
                break
            }
            
            // Extract message
            let messageData: Data
            if includeDelimiter {
                // Include delimiter in message
                let endIndex = state.buffer.index(range.lowerBound, offsetBy: delimiter.count)
                messageData = state.buffer[..<endIndex]
            } else {
                // Exclude delimiter from message
                messageData = state.buffer[..<range.lowerBound]
            }
            
            messages.append(Message(messageData))
            
            // Remove processed data including delimiter
            let removeCount = range.upperBound - state.buffer.startIndex
            state.buffer = Data(state.buffer.dropFirst(removeCount))
        }
        
        return (messages, Data())
    }
}

/// Common delimiter framers
extension DelimiterFramer {
    /// Line-delimited framer using LF (\n)
    public static var lineDelimited: DelimiterFramer {
        DelimiterFramer(delimiter: "\n")
    }
    
    /// CRLF-delimited framer using CRLF (\r\n)
    public static var crlfDelimited: DelimiterFramer {
        DelimiterFramer(delimiter: "\r\n")
    }
    
    /// Null-delimited framer using null byte (\0)
    public static var nullDelimited: DelimiterFramer {
        DelimiterFramer(delimiter: Data([0]))
    }
}