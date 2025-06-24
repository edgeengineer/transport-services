#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A framer for HTTP/1.x message framing.
///
/// This framer handles HTTP request/response framing including:
/// - Header parsing with CRLF delimiters
/// - Content-Length based body framing
/// - Chunked transfer encoding (simplified)
public struct HTTPFramer: MessageFramer, Sendable {
    
    public enum Mode: Sendable {
        case client  // Expects responses
        case server  // Expects requests
    }
    
    private let mode: Mode
    private let maxHeaderSize: Int
    private let maxBodySize: Int
    
    /// Parsing state for HTTP messages
    private final class ParsingState: @unchecked Sendable {
        var buffer = Data()
        var expectingBody = false
        var contentLength: Int?
        var isChunked = false
        var headersData: Data?
    }
    
    private let state = ParsingState()
    
    /// Creates a new HTTP framer
    public init(mode: Mode = .server,
                maxHeaderSize: Int = 8192,
                maxBodySize: Int = 10 * 1024 * 1024) { // 10MB
        self.mode = mode
        self.maxHeaderSize = maxHeaderSize
        self.maxBodySize = maxBodySize
    }
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        // For simplicity, assume the message is already a valid HTTP message
        // In a real implementation, we'd build proper HTTP formatting
        return [message.data]
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        var messages: [Message] = []
        
        state.buffer.append(bytes)
        
        while !state.buffer.isEmpty {
            if !state.expectingBody {
                // Look for end of headers (CRLFCRLF)
                let crlfcrlf = Data("\r\n\r\n".utf8)
                guard let headerEnd = state.buffer.range(of: crlfcrlf) else {
                    // Headers incomplete
                    if state.buffer.count > maxHeaderSize {
                        throw TransportError.receiveFailure("HTTP headers too large")
                    }
                    break
                }
                
                // Extract headers (excluding the final CRLF CRLF)
                let headersData = state.buffer[..<headerEnd.upperBound]
                let headersOnlyData = state.buffer[..<headerEnd.lowerBound]
                let headers = String(data: headersOnlyData, encoding: .utf8) ?? ""
                
                // Parse Content-Length
                if let contentLengthMatch = headers.range(of: "Content-Length: ", options: .caseInsensitive) {
                    let start = headers.index(contentLengthMatch.upperBound, offsetBy: 0)
                    let substring = headers[start...]
                    let end = substring.firstIndex(where: { $0 == "\r" || $0 == "\n" }) ?? headers.endIndex
                    let lengthStr = String(headers[start..<end])
                    state.contentLength = Int(lengthStr.trimmingCharacters(in: .whitespaces))
                    state.expectingBody = (state.contentLength ?? 0) > 0
                }
                
                // Check for chunked encoding
                if headers.range(of: "Transfer-Encoding: chunked", options: .caseInsensitive) != nil {
                    state.isChunked = true
                    state.expectingBody = true
                }
                
                // Remove headers from buffer
                let dropCount = headerEnd.upperBound - state.buffer.startIndex
                state.buffer = Data(state.buffer.dropFirst(dropCount))
                
                if !state.expectingBody {
                    // Message complete (no body)
                    messages.append(Message(headersData))
                } else {
                    // Store headers for later when we have the complete message
                    state.headersData = headersData
                }
            } else {
                // Expecting body
                if let contentLength = state.contentLength {
                    // Content-Length based body
                    if state.buffer.count >= contentLength {
                        let bodyData = state.buffer[..<contentLength]
                        messages.append(Message(bodyData))
                        
                        state.buffer = Data(state.buffer.dropFirst(contentLength))
                        state.expectingBody = false
                        state.contentLength = nil
                        state.headersData = nil
                    } else {
                        // Body incomplete
                        if state.buffer.count > maxBodySize {
                            throw TransportError.receiveFailure("HTTP body too large")
                        }
                        break
                    }
                } else if state.isChunked {
                    // Simplified chunked parsing - just look for 0\r\n\r\n
                    let endChunk = Data("0\r\n\r\n".utf8)
                    if let chunkEnd = state.buffer.range(of: endChunk) {
                        let bodyData = state.buffer[..<chunkEnd.upperBound]
                        messages.append(Message(bodyData))
                        
                        let dropCount = chunkEnd.upperBound - state.buffer.startIndex
                        state.buffer = Data(state.buffer.dropFirst(dropCount))
                        state.expectingBody = false
                        state.isChunked = false
                        state.headersData = nil
                    } else {
                        // Chunks incomplete
                        break
                    }
                }
            }
        }
        
        return (messages, Data())
    }
}