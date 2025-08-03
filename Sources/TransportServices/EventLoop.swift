//
//  EventLoop.swift
//  
//
//  Maximilian Alexander
//


#if !hasFeature(Embedded)
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
#endif

#if canImport(Dispatch)
import Dispatch

internal final class EventLoop: @unchecked Sendable {
    private static let singleton = EventLoop()
    private let queue: DispatchQueue

    private init() {
        self.queue = DispatchQueue(label: "taps.eventloop", qos: .userInitiated)
    }

    public static func execute(_ block: @escaping @Sendable () -> Void) {
        singleton.queue.async(execute: block)
    }
}
#elseif os(Linux)
#if canImport(Musl)
import Musl
typealias PlatformLock = MutexLock
#elseif canImport(Glibc)
import Glibc
import Foundation
typealias PlatformLock = NSLock
#else
#error("Unsupported C library")
#endif

/// Simple mutex lock for Musl compatibility
#if canImport(Musl)
internal final class MutexLock: @unchecked Sendable {
    private var mutex = pthread_mutex_t()
    
    init() {
        var attr = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_NORMAL)
        pthread_mutex_init(&mutex, &attr)
        pthread_mutexattr_destroy(&attr)
    }
    
    deinit {
        pthread_mutex_destroy(&mutex)
    }
    
    func lock() {
        pthread_mutex_lock(&mutex)
    }
    
    func unlock() {
        pthread_mutex_unlock(&mutex)
    }
}
#endif

/// Linux EventLoop implementation using epoll for async event handling
internal final class EventLoop: @unchecked Sendable {
    private static let singleton = EventLoop()
    
    private let epollFd: Int32
    private let eventFd: Int32
    private let running = Atomic<Bool>(true)
    private let thread: Thread
    private let pendingTasks = Atomic<[() -> Void]>([])
    
    private init() {
        // Create epoll instance
        self.epollFd = epoll_create1(Int32(EPOLL_CLOEXEC))
        guard self.epollFd >= 0 else {
            fatalError("Failed to create epoll instance: \(String(cString: strerror(errno)))")
        }
        
        // Create eventfd for task notifications
        self.eventFd = eventfd(0, Int32(EFD_CLOEXEC | EFD_NONBLOCK))
        guard self.eventFd >= 0 else {
            fatalError("Failed to create eventfd: \(String(cString: strerror(errno)))")
        }
        
        // Register eventfd with epoll
        var event = epoll_event()
        event.events = UInt32(EPOLLIN | EPOLLET)
        event.data.fd = self.eventFd
        
        let result = epoll_ctl(self.epollFd, EPOLL_CTL_ADD, self.eventFd, &event)
        guard result == 0 else {
            fatalError("Failed to add eventfd to epoll: \(String(cString: strerror(errno)))")
        }
        
        // Start event loop thread
        self.thread = Thread { [weak self] in
            self?.run()
        }
        self.thread.start()
    }
    
    deinit {
        running.store(false)
        
        // Wake up the event loop to exit
        let value: UInt64 = 1
        _ = write(eventFd, &value, MemoryLayout<UInt64>.size)
        
        // Close file descriptors
        close(eventFd)
        close(epollFd)
    }
    
    private func run() {
        var events = Array<epoll_event>(repeating: epoll_event(), count: 64)
        
        while running.load() {
            let nfds = epoll_wait(epollFd, &events, Int32(events.count), -1)
            
            if nfds < 0 {
                if errno == EINTR {
                    continue
                }
                print("epoll_wait error: \(String(cString: strerror(errno)))")
                break
            }
            
            for i in 0..<Int(nfds) {
                if events[i].data.fd == eventFd {
                    // Handle task notifications
                    handleTaskNotification()
                } else {
                    // Handle other file descriptors (for future socket handling)
                    handleSocketEvent(fd: events[i].data.fd, events: events[i].events)
                }
            }
        }
    }
    
    private func handleTaskNotification() {
        // Clear the eventfd
        var value: UInt64 = 0
        _ = read(eventFd, &value, MemoryLayout<UInt64>.size)
        
        // Execute pending tasks
        let tasks = pendingTasks.exchange([])
        for task in tasks {
            task()
        }
    }
    
    private func handleSocketEvent(fd: Int32, events: UInt32) {
        // This will be implemented when we add socket support
        // For now, this is a placeholder for future socket handling
    }
    
    /// Execute a block asynchronously on the event loop
    public static func execute(_ block: @escaping @Sendable () -> Void) {
        singleton.pendingTasks.update { tasks in
            tasks.append(block)
        }
        
        // Wake up the event loop
        var value: UInt64 = 1
        _ = write(singleton.eventFd, &value, MemoryLayout<UInt64>.size)
    }
    
    /// Register a socket for monitoring
    internal static func registerSocket(_ fd: Int32, events: UInt32, handler: @escaping () -> Void) -> Bool {
        var event = epoll_event()
        event.events = events
        event.data.fd = fd
        
        let result = epoll_ctl(singleton.epollFd, EPOLL_CTL_ADD, fd, &event)
        return result == 0
    }
    
    /// Unregister a socket from monitoring
    internal static func unregisterSocket(_ fd: Int32) {
        epoll_ctl(singleton.epollFd, EPOLL_CTL_DEL, fd, nil)
    }
    
    /// Modify socket monitoring events
    internal static func modifySocket(_ fd: Int32, events: UInt32) -> Bool {
        var event = epoll_event()
        event.events = events
        event.data.fd = fd
        
        let result = epoll_ctl(singleton.epollFd, EPOLL_CTL_MOD, fd, &event)
        return result == 0
    }
}

/// Simple atomic wrapper for thread-safe operations
private final class Atomic<T>: @unchecked Sendable {
    private var value: T
    private let lock = PlatformLock()
    
    init(_ value: T) {
        self.value = value
    }
    
    func load() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    
    func store(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
    
    func exchange(_ newValue: T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let oldValue = value
        value = newValue
        return oldValue
    }
    
    func update(_ transform: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&value)
    }
}
#elseif os(Windows)
import WinSDK
import Foundation

/// Windows EventLoop implementation using I/O Completion Ports (IOCP)
internal final class EventLoop: @unchecked Sendable {
    private static let singleton = EventLoop()
    
    private let iocpHandle: HANDLE
    private let running = Atomic<Bool>(true)
    private let thread: Thread
    private let pendingTasks = Atomic<[() -> Void]>([])
    
    // Custom completion key for task notifications
    private static let TASK_NOTIFICATION_KEY: ULONG_PTR = 1
    
    private init() {
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
            
            if result == FALSE {
                let error = GetLastError()
                if error == ERROR_ABANDONED_WAIT_0 {
                    // IOCP handle was closed
                    break
                }
                print("GetQueuedCompletionStatus error: \(error)")
                continue
            }
            
            // Check if this is a task notification
            if completionKey == Self.TASK_NOTIFICATION_KEY {
                handleTaskNotification()
            } else if let overlapped = overlapped {
                // Handle I/O completion
                handleIOCompletion(overlapped: overlapped, bytesTransferred: bytesTransferred)
            }
        }
    }
    
    private func handleTaskNotification() {
        // Execute pending tasks
        let tasks = pendingTasks.exchange([])
        for task in tasks {
            task()
        }
    }
    
    private func handleIOCompletion(overlapped: LPOVERLAPPED, bytesTransferred: DWORD) {
        // This will be implemented when we add socket support
        // The overlapped structure will contain context for the I/O operation
    }
    
    /// Execute a block asynchronously on the event loop
    public static func execute(_ block: @escaping @Sendable () -> Void) {
        singleton.pendingTasks.update { tasks in
            tasks.append(block)
        }
        
        // Post completion status to wake up the event loop
        PostQueuedCompletionStatus(
            singleton.iocpHandle,
            0,
            TASK_NOTIFICATION_KEY,
            nil
        )
    }
    
    /// Associate a socket with the IOCP
    internal static func associateSocket(_ socket: SOCKET) -> Bool {
        let result = CreateIoCompletionPort(
            HANDLE(socket),
            singleton.iocpHandle,
            ULONG_PTR(socket),
            0
        )
        return result != nil && result != INVALID_HANDLE_VALUE
    }
    
    /// Post an I/O completion
    internal static func postCompletion(socket: SOCKET, overlapped: LPOVERLAPPED, bytes: DWORD = 0) {
        PostQueuedCompletionStatus(
            singleton.iocpHandle,
            bytes,
            ULONG_PTR(socket),
            overlapped
        )
    }
}

/// Simple atomic wrapper for thread-safe operations (Windows version)
private final class Atomic<T>: @unchecked Sendable {
    private var value: T
    private var criticalSection = CRITICAL_SECTION()
    
    init(_ value: T) {
        self.value = value
        InitializeCriticalSection(&criticalSection)
    }
    
    deinit {
        DeleteCriticalSection(&criticalSection)
    }
    
    func load() -> T {
        EnterCriticalSection(&criticalSection)
        defer { LeaveCriticalSection(&criticalSection) }
        return value
    }
    
    func store(_ newValue: T) {
        EnterCriticalSection(&criticalSection)
        defer { LeaveCriticalSection(&criticalSection) }
        value = newValue
    }
    
    func exchange(_ newValue: T) -> T {
        EnterCriticalSection(&criticalSection)
        defer { LeaveCriticalSection(&criticalSection) }
        let oldValue = value
        value = newValue
        return oldValue
    }
    
    func update(_ transform: (inout T) -> Void) {
        EnterCriticalSection(&criticalSection)
        defer { LeaveCriticalSection(&criticalSection) }
        transform(&value)
    }
}
#endif
