//
//  EventLoop.swift
//  
//
//  Maximilian Alexander
//

/// Unified EventLoop interface that delegates to platform-specific implementations
internal final class EventLoop: @unchecked Sendable {
    private static let singleton = EventLoop()
    
    #if canImport(Dispatch)
    private let platformLoop = AppleEventLoop()
    #elseif os(Linux)
    private let platformLoop = LinuxEventLoop()
    #elseif os(Windows)
    private let platformLoop = WindowsEventLoop()
    #endif
    
    private init() {}
    
    /// Execute a block asynchronously on the event loop
    public static func execute(_ block: @escaping @Sendable () -> Void) {
        singleton.platformLoop.execute(block)
    }
    
    #if canImport(Dispatch)
    /// Schedule a block to execute after a delay (Apple platforms only)
    public static func schedule(after delay: Double, _ block: @escaping @Sendable () -> Void) {
        singleton.platformLoop.schedule(after: delay, block)
    }
    
    /// Execute a block synchronously on the event loop (Apple platforms only)
    public static func executeSync<T>(_ block: () throws -> T) rethrows -> T {
        try singleton.platformLoop.executeSync(block)
    }
    #endif
    
    #if os(Linux)
    /// Register a socket for monitoring (Linux only)
    internal static func registerSocket(_ fd: Int32, events: UInt32, handler: @escaping () -> Void) -> Bool {
        singleton.platformLoop.registerSocket(fd, events: events, handler: handler)
    }
    
    /// Unregister a socket from monitoring (Linux only)
    internal static func unregisterSocket(_ fd: Int32) {
        singleton.platformLoop.unregisterSocket(fd)
    }
    
    /// Modify socket monitoring events (Linux only)
    internal static func modifySocket(_ fd: Int32, events: UInt32) -> Bool {
        singleton.platformLoop.modifySocket(fd, events: events)
    }
    #endif
    
    #if os(Windows)
    /// Associate a socket with the IOCP (Windows only)
    internal static func associateSocket(_ socket: SOCKET, handler: @escaping (DWORD) -> Void) -> Bool {
        singleton.platformLoop.associateSocket(socket, handler: handler)
    }
    
    /// Disassociate a socket from the IOCP (Windows only)
    internal static func disassociateSocket(_ socket: SOCKET) {
        singleton.platformLoop.disassociateSocket(socket)
    }
    
    /// Post an I/O completion for a socket (Windows only)
    internal static func postSocketCompletion(_ socket: SOCKET, bytes: DWORD = 0) {
        singleton.platformLoop.postSocketCompletion(socket, bytes: bytes)
    }
    
    /// Submit an overlapped I/O operation (Windows only)
    internal static func submitOverlappedIO(_ socket: SOCKET, overlapped: LPOVERLAPPED) {
        singleton.platformLoop.submitOverlappedIO(socket, overlapped: overlapped)
    }
    #endif
}