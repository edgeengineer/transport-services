#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOConcurrencyHelpers

/// A channel handler that uses configured MessageFramer instances to handle message framing
final class ConfiguredFramingHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Message
    typealias OutboundIn = Message
    typealias OutboundOut = ByteBuffer
    
    private let framers: [any MessageFramer]
    private var inboundBuffer = Data()
    private let stateLock = NIOLock()
    private weak var connection: Connection?
    private var hasFiredConnectionEvents = false
    
    init(framers: [any MessageFramer], connection: Connection? = nil) {
        self.framers = framers
        self.connection = connection
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // Fire connection events to framers if we have a connection
        if let connection = connection, !hasFiredConnectionEvents {
            hasFiredConnectionEvents = true
            
            // Use a detached task to avoid blocking the event loop
            Task.detached { [weak connection, framers] in
                guard let connection = connection else { return }
                
                // Notify all framers about connection open
                for framer in framers {
                    do {
                        _ = try await framer.connectionDidOpen(connection)
                    } catch {
                        // Log error but continue with other framers
                        print("Framer connectionDidOpen error: \(error)")
                    }
                }
            }
        }
        
        context.fireChannelActive()
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        // Fire connection close events to framers
        if let connection = connection, hasFiredConnectionEvents {
            Task.detached { [weak connection, framers] in
                guard let connection = connection else { return }
                
                // Notify all framers about connection close
                for framer in framers {
                    await framer.connectionDidClose(connection)
                }
            }
        }
        
        context.fireChannelInactive()
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard buffer.readableBytes > 0 else { return }
        
        let newData = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
        
        // Append to buffer
        stateLock.withLock {
            inboundBuffer.append(newData)
        }
        
        // Get current buffer
        let currentData = stateLock.withLock { inboundBuffer }
        
        if framers.isEmpty {
            // No framers - pass through as-is
            if !currentData.isEmpty {
                let message = Message(currentData)
                context.fireChannelRead(wrapInboundOut(message))
                context.fireChannelReadComplete()
                stateLock.withLock {
                    inboundBuffer = Data()
                }
            }
        } else {
            // With framers, we process asynchronously but deliver synchronously
            let channel = context.channel
            
            // Process framers in a detached task
            Task.detached { [weak self, framers] in
                guard let self = self else { return }
                
                do {
                    // Process through framers
                    var processData = currentData
                    var allMessages: [Message] = []
                    
                    for framer in framers.reversed() {
                        let result = try await framer.parseInbound(processData)
                        allMessages.append(contentsOf: result.messages)
                        processData = result.remainder
                    }
                    
                    // Update buffer with remainder
                    self.stateLock.withLock {
                        self.inboundBuffer = processData
                    }
                    
                    // Send messages to pipeline on event loop
                    if !allMessages.isEmpty {
                        let handler = self
                        let messagesToSend = allMessages
                        try await channel.eventLoop.submit {
                            for message in messagesToSend {
                                channel.pipeline.fireChannelRead(handler.wrapInboundOut(message))
                            }
                            channel.pipeline.fireChannelReadComplete()
                        }.get()
                    }
                } catch {
                    try? await channel.eventLoop.submit {
                        channel.pipeline.fireErrorCaught(error)
                    }.get()
                }
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        
        if framers.isEmpty {
            // No framers - pass through as-is
            var buffer = context.channel.allocator.buffer(capacity: message.data.count)
            buffer.writeBytes(message.data)
            context.write(wrapOutboundOut(buffer), promise: promise)
        } else {
            // With framers, process asynchronously
            let channel = context.channel
            
            Task.detached { [weak self, framers] in
                guard let self = self else {
                    promise?.fail(TransportError.sendFailure("Handler deallocated"))
                    return
                }
                
                do {
                    // Process through framers
                    var currentData = [message.data]
                    
                    for framer in framers {
                        var framedData: [Data] = []
                        for data in currentData {
                            let framedMessage = Message(data, context: message.context)
                            let result = try await framer.frameOutbound(framedMessage)
                            framedData.append(contentsOf: result)
                        }
                        currentData = framedData
                    }
                    
                    // Combine all data chunks
                    var finalData = Data()
                    for chunk in currentData {
                        finalData.append(chunk)
                    }
                    
                    // Write to channel on event loop
                    let handler = self
                    let dataToWrite = finalData
                    try await channel.eventLoop.submit {
                        var buffer = channel.allocator.buffer(capacity: dataToWrite.count)
                        buffer.writeBytes(dataToWrite)
                        _ = channel.write(handler.wrapOutboundOut(buffer), promise: promise)
                    }.get()
                } catch {
                    promise?.fail(error)
                }
            }
        }
    }
    
    /// Updates the connection reference (used when connection is created after handler)
    func setConnection(_ connection: Connection) async {
        self.connection = connection
        
        // If channel is already active and we haven't fired events, do it now
        if hasFiredConnectionEvents == false {
            hasFiredConnectionEvents = true
            
            // Notify all framers about connection open
            for framer in framers {
                do {
                    _ = try await framer.connectionDidOpen(connection)
                } catch {
                    // Log error but continue with other framers
                    print("Framer connectionDidOpen error: \(error)")
                }
            }
        }
    }
}