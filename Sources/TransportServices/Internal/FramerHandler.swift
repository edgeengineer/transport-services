import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Protocol for framing handlers that can be used in the NIO pipeline
protocol FramingHandlerProtocol: ChannelDuplexHandler where
    InboundIn == ByteBuffer,
    InboundOut == Message,
    OutboundIn == Message,
    OutboundOut == ByteBuffer {
}

/// Adaptive framing handler that can use MessageFramer implementations
final class FramerHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Message
    typealias OutboundIn = Message
    typealias OutboundOut = ByteBuffer
    
    private let framers: [any MessageFramer]
    private let connection: Connection
    private var inboundBuffer = Data()
    
    init(framers: [any MessageFramer], connection: Connection) {
        self.framers = framers
        self.connection = connection
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard buffer.readableBytes > 0 else { return }
        
        let newData = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
        
        if framers.isEmpty {
            // No framers - use simple length-prefix framing
            handleLengthPrefixFraming(context: context, data: newData)
        } else {
            // Use MessageFramer protocol
            // For now, use the first framer only
            // Full implementation would chain framers
            handleFramerProtocol(context: context, data: newData)
        }
    }
    
    private func handleLengthPrefixFraming(context: ChannelHandlerContext, data: Data) {
        inboundBuffer.append(data)
        var messages: [Message] = []
        
        while inboundBuffer.count >= 4 {
            let length = UInt32(inboundBuffer[0]) << 24 |
                        UInt32(inboundBuffer[1]) << 16 |
                        UInt32(inboundBuffer[2]) << 8 |
                        UInt32(inboundBuffer[3])
            
            guard length <= 1024 * 1024 else {
                inboundBuffer = Data()
                context.fireErrorCaught(TransportError.receiveFailure("Message too large"))
                context.close(promise: nil)
                return
            }
            
            let totalSize = 4 + Int(length)
            guard inboundBuffer.count >= totalSize else { break }
            
            let messageData = inboundBuffer[4..<totalSize]
            messages.append(Message(Data(messageData)))
            inboundBuffer = Data(inboundBuffer.dropFirst(totalSize))
        }
        
        for message in messages {
            context.fireChannelRead(wrapInboundOut(message))
        }
        
        if !messages.isEmpty {
            context.fireChannelReadComplete()
        }
    }
    
    private func handleFramerProtocol(context: ChannelHandlerContext, data: Data) {
        // This would need to be async in a full implementation
        // For now, just pass through
        let message = Message(data)
        context.fireChannelRead(wrapInboundOut(message))
        context.fireChannelReadComplete()
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        
        if framers.isEmpty {
            // Simple length-prefix framing
            writeLengthPrefixFrame(context: context, message: message, promise: promise)
        } else {
            // Use MessageFramer protocol
            // For now, just pass through
            writeFramerProtocol(context: context, message: message, promise: promise)
        }
    }
    
    private func writeLengthPrefixFrame(context: ChannelHandlerContext, 
                                        message: Message, 
                                        promise: EventLoopPromise<Void>?) {
        let length = UInt32(message.data.count)
        guard length <= 1024 * 1024 else {
            promise?.fail(TransportError.sendFailure("Message too large"))
            return
        }
        
        var buffer = context.channel.allocator.buffer(capacity: 4 + Int(length))
        buffer.writeInteger(length, endianness: .big, as: UInt32.self)
        if !message.data.isEmpty {
            buffer.writeBytes(message.data)
        }
        
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
    
    private func writeFramerProtocol(context: ChannelHandlerContext,
                                     message: Message,
                                     promise: EventLoopPromise<Void>?) {
        // This would need to be async in a full implementation
        var buffer = context.channel.allocator.buffer(capacity: message.data.count)
        buffer.writeBytes(message.data)
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
}

/// Factory for creating appropriate framing handlers
enum FramingHandlerFactory {
    static func createHandler(framers: [any MessageFramer], 
                              connection: Connection) -> ChannelHandler {
        if framers.isEmpty {
            // Use simple length-prefix handler
            return SimpleFramingHandler()
        } else {
            // Use full framer handler
            // For now, still use SimpleFramingHandler
            // Full implementation would use FramerHandler
            return SimpleFramingHandler()
        }
    }
}