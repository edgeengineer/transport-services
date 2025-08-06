//
//  AppleEventLoop.swift
//  
//
//  Event loop implementation for Apple platforms using Grand Central Dispatch
//

#if canImport(Dispatch) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
import Dispatch

/// Apple platform EventLoop implementation using Grand Central Dispatch
internal final class AppleEventLoop: @unchecked Sendable {
    private let queue: DispatchQueue
    
    init() {
        self.queue = DispatchQueue(label: "taps.eventloop", qos: .userInitiated)
    }
    
    /// Execute a block asynchronously on the event loop
    func execute(_ block: @escaping @Sendable () -> Void) {
        queue.async(execute: block)
    }
    
    /// Schedule a block to execute after a delay
    func schedule(after delay: Double, _ block: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: block)
    }
    
    /// Execute a block synchronously on the event loop
    func executeSync<T>(_ block: () throws -> T) rethrows -> T {
        try queue.sync(execute: block)
    }
    
    /// Create a dispatch source for monitoring file descriptors (if needed for future use)
    func monitorFileDescriptor(_ fd: Int32, events: DispatchSource.FileSystemEvent, handler: @escaping () -> Void) -> DispatchSource {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: events,
            queue: queue
        )
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }
}
#endif