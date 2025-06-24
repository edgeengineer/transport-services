import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Simple message framing handler with length-prefix framing
final class SimpleFramingHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Message
    typealias OutboundIn = Message
    typealias OutboundOut = ByteBuffer
    
    private var inboundBuffer = Data()
    private let maxMessageSize: Int = 1024 * 1024 // 1MB
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard buffer.readableBytes > 0 else { return }
        
        let newData = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
        
        // Add new data to buffer
        inboundBuffer.append(newData)
        
        // Parse complete messages
        var messages: [Message] = []
        
        while inboundBuffer.count >= 4 {
            // Read length prefix (big-endian)
            let length = UInt32(inboundBuffer[0]) << 24 |
                        UInt32(inboundBuffer[1]) << 16 |
                        UInt32(inboundBuffer[2]) << 8 |
                        UInt32(inboundBuffer[3])
            
            // Sanity check
            guard length > 0 && length <= maxMessageSize else {
                // Invalid message size - reset buffer and close
                inboundBuffer = Data()
                context.fireErrorCaught(TransportError.receiveFailure("Invalid message size: \(length) bytes"))
                context.close(promise: nil)
                return
            }
            
            // Check if we have the complete message
            let totalSize = 4 + Int(length)
            guard inboundBuffer.count >= totalSize else {
                // Not enough data yet
                break
            }
            
            // Extract message data safely
            let messageStart = inboundBuffer.index(inboundBuffer.startIndex, offsetBy: 4)
            let messageEnd = inboundBuffer.index(inboundBuffer.startIndex, offsetBy: totalSize)
            let messageData = inboundBuffer[messageStart..<messageEnd]
            messages.append(Message(Data(messageData)))
            
            // Remove processed data from buffer
            inboundBuffer = Data(inboundBuffer.dropFirst(totalSize))
        }
        
        // Fire messages downstream
        for message in messages {
            context.fireChannelRead(wrapInboundOut(message))
        }
        
        if !messages.isEmpty {
            context.fireChannelReadComplete()
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        let length = UInt32(message.data.count)
        
        // Allow empty messages but check max size
        guard length <= maxMessageSize else {
            promise?.fail(TransportError.sendFailure("Message too large: \(length) bytes"))
            return
        }
        
        var buffer = context.channel.allocator.buffer(capacity: 4 + Int(length))
        
        // Write 4-byte length in big-endian
        buffer.writeInteger(length, endianness: .big, as: UInt32.self)
        
        // Write message data if not empty
        if !message.data.isEmpty {
            buffer.writeBytes(message.data)
        }
        
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
}

/// No-op message framing handler that passes messages through unchanged
final class NoOpFramingHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Message
    typealias OutboundIn = Message
    typealias OutboundOut = ByteBuffer
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        
        // Treat entire buffer as a message
        let message = Message(Data(buffer.readableBytesView))
        
        context.fireChannelRead(wrapInboundOut(message))
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        
        var buffer = context.channel.allocator.buffer(capacity: message.data.count)
        buffer.writeBytes(message.data)
        
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
}