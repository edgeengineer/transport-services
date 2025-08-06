//
//  WindowsEventLoop.swift
//  
//
//  Event loop implementation for Windows using I/O Completion Ports
//

#if os(Windows)
import WinSDK
import Foundation

/// Windows EventLoop implementation using I/O Completion Ports (IOCP)
internal final class WindowsEventLoop: @unchecked Sendable {
    private let iocpHandle: HANDLE
    private let running = AtomicBool(true)
    private let thread: Thread
    private let pendingTasks = AtomicArray<() -> Void>()
    
    // Custom completion keys
    private enum CompletionKey {
        static let taskNotification: ULONG_PTR = 1
        static let socketBase: ULONG_PTR = 1000
    }
    
    // Track socket handlers
    private var socketHandlers = [SOCKET: SocketContext]()
    private let handlersLock = CriticalSectionLock()
    
    private struct SocketContext {
        let socket: SOCKET
        let handler: (DWORD) -> Void
        var overlapped: OVERLAPPED
    }
    
    init() {
        // Create I/O Completion Port
        self.iocpHandle = CreateIoCompletionPort(INVALID_HANDLE_VALUE, nil, 0, 0)
        guard self.iocpHandle != nil && self.iocpHandle != INVALID_HANDLE_VALUE else {
            fatalError("Failed to create IOCP: \(GetLastError())")
        }
        
        // Start event loop thread
        self.thread = Thread { [weak self] in
            self?.run()
        }
        self.thread.start()
    }
    
    deinit {
        running.store(false)
        
        // Post a completion status to wake up the event loop
        PostQueuedCompletionStatus(iocpHandle, 0, 0, nil)
        
        // Close IOCP handle
        CloseHandle(iocpHandle)
    }
    
    private func run() {
        var bytesTransferred: DWORD = 0
        var completionKey: ULONG_PTR = 0
        var overlapped: LPOVERLAPPED? = nil
        
        while running.load() {
            // Wait for completion status
            let result = GetQueuedCompletionStatus(
                iocpHandle,
                &bytesTransferred,
                &completionKey,
                &overlapped,
                INFINITE
            )
            
            if Bool(result) == false {
                let error = GetLastError()
                if error == ERROR_ABANDONED_WAIT_0 {
                    // IOCP handle was closed
                    break
                }
                
                // Check if this is a timeout or real error
                if overlapped == nil && error == WAIT_TIMEOUT {
                    continue
                }
                
                // GetQueuedCompletionStatus error
                
                // Handle I/O errors for specific sockets
                if completionKey >= CompletionKey.socketBase {
                    handleIOError(completionKey: completionKey, error: error)
                }
                continue
            }
            
            // Handle different completion types
            if completionKey == CompletionKey.taskNotification {
                handleTaskNotification()
            } else if completionKey >= CompletionKey.socketBase {
                // Handle socket I/O completion
                handleSocketCompletion(
                    completionKey: completionKey,
                    bytesTransferred: bytesTransferred,
                    overlapped: overlapped
                )
            }
        }
    }
    
    private func handleTaskNotification() {
        // Execute pending tasks
        let tasks = pendingTasks.exchangeAll([])
        for task in tasks {
            task()
        }
    }
    
    private func handleSocketCompletion(completionKey: ULONG_PTR, bytesTransferred: DWORD, overlapped: LPOVERLAPPED?) {
        let socket = SOCKET(completionKey - CompletionKey.socketBase)
        
        handlersLock.withLock {
            if let context = socketHandlers[socket] {
                context.handler(bytesTransferred)
            }
        }
    }
    
    private func handleIOError(completionKey: ULONG_PTR, error: DWORD) {
        let socket = SOCKET(completionKey - CompletionKey.socketBase)
        
        handlersLock.withLock {
            if let context = socketHandlers[socket] {
                // Call handler with 0 bytes to indicate error
                context.handler(0)
            }
        }
    }
    
    /// Execute a block asynchronously on the event loop
    func execute(_ block: @escaping @Sendable () -> Void) {
        pendingTasks.append(block)
        
        // Post completion status to wake up the event loop
        PostQueuedCompletionStatus(
            iocpHandle,
            0,
            CompletionKey.taskNotification,
            nil
        )
    }
    
    /// Associate a socket with the IOCP
    func associateSocket(_ socket: SOCKET, handler: @escaping (DWORD) -> Void) -> Bool {
        let completionKey = CompletionKey.socketBase + ULONG_PTR(socket)
        
        // Convert socket to HANDLE using bitPattern
        let socketHandle = HANDLE(bitPattern: Int(socket))
        
        let result = CreateIoCompletionPort(
            socketHandle,
            iocpHandle,
            completionKey,
            0
        )
        
        if result != nil && result != INVALID_HANDLE_VALUE {
            handlersLock.withLock {
                var context = SocketContext(
                    socket: socket,
                    handler: handler,
                    overlapped: OVERLAPPED()
                )
                socketHandlers[socket] = context
            }
            return true
        }
        return false
    }
    
    /// Disassociate a socket from the IOCP
    func disassociateSocket(_ socket: SOCKET) {
        handlersLock.withLock {
            socketHandlers.removeValue(forKey: socket)
        }
    }
    
    /// Post an I/O completion for a socket
    func postSocketCompletion(_ socket: SOCKET, bytes: DWORD = 0) {
        let completionKey = CompletionKey.socketBase + ULONG_PTR(socket)
        
        PostQueuedCompletionStatus(
            iocpHandle,
            bytes,
            completionKey,
            nil
        )
    }
    
    /// Submit an overlapped I/O operation
    func submitOverlappedIO(_ socket: SOCKET, overlapped: LPOVERLAPPED) {
        // The overlapped structure will be used by Windows for async I/O
        // The completion will be posted automatically when the operation completes
    }
}

// MARK: - Thread-safe utilities for Windows

/// Thread-safe boolean for Windows
private final class AtomicBool: @unchecked Sendable {
    private var value: Bool
    private let lock = CriticalSectionLock()
    
    init(_ value: Bool) {
        self.value = value
    }
    
    func load() -> Bool {
        lock.withLock { value }
    }
    
    func store(_ newValue: Bool) {
        lock.withLock { value = newValue }
    }
}

/// Thread-safe array for Windows
private final class AtomicArray<T>: @unchecked Sendable {
    private var array: [T] = []
    private let lock = CriticalSectionLock()
    
    func append(_ element: T) {
        lock.withLock { array.append(element) }
    }
    
    func exchangeAll(_ newArray: [T]) -> [T] {
        lock.withLock {
            let old = array
            array = newArray
            return old
        }
    }
}

/// Critical section lock for Windows
private final class CriticalSectionLock: @unchecked Sendable {
    private var criticalSection = CRITICAL_SECTION()
    
    init() {
        InitializeCriticalSection(&criticalSection)
    }
    
    deinit {
        DeleteCriticalSection(&criticalSection)
    }
    
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        EnterCriticalSection(&criticalSection)
        defer { LeaveCriticalSection(&criticalSection) }
        return try body()
    }
}

#endif