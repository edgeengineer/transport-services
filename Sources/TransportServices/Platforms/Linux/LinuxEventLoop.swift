//
//  LinuxEventLoop.swift
//  
//
//  Event loop implementation for Linux using epoll
//

#if os(Linux)
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
import Foundation
#else
#error("Unsupported C library")
#endif

// Define epoll structures for Swift
struct epoll_data_t {
    var fd: Int32 = 0
}

struct epoll_event {
    var events: UInt32
    var data: epoll_data_t
    
    init() {
        self.events = 0
        self.data = epoll_data_t()
    }
}

// Declare epoll functions
@_silgen_name("epoll_create1")
func epoll_create1(_ flags: Int32) -> Int32

@_silgen_name("epoll_ctl")
func epoll_ctl(_ epfd: Int32, _ op: Int32, _ fd: Int32, _ event: UnsafeMutablePointer<epoll_event>?) -> Int32

@_silgen_name("epoll_wait")
func epoll_wait(_ epfd: Int32, _ events: UnsafeMutablePointer<epoll_event>?, _ maxevents: Int32, _ timeout: Int32) -> Int32

@_silgen_name("eventfd")
func eventfd(_ count: UInt32, _ flags: Int32) -> Int32

/// Linux EventLoop implementation using epoll for async event handling
internal final class LinuxEventLoop: @unchecked Sendable {
    private let epollFd: Int32
    private let eventFd: Int32
    private let running = AtomicBool(true)
    private var thread: Thread!
    private let pendingTasks = AtomicArray<() -> Void>()
    private var socketHandlers = [Int32: () -> Void]()
    private let handlersLock = ThreadLock()
    
    init() {
        // Create epoll instance
        self.epollFd = epoll_create1(LinuxCompat.EPOLL_CLOEXEC)
        guard self.epollFd >= 0 else {
            fatalError("Failed to create epoll instance: \(String(cString: strerror(errno)))")
        }
        
        // Create eventfd for task notifications
        self.eventFd = eventfd(0, LinuxCompat.EFD_CLOEXEC | LinuxCompat.EFD_NONBLOCK)
        guard self.eventFd >= 0 else {
            fatalError("Failed to create eventfd: \(String(cString: strerror(errno)))")
        }
        
        // Register eventfd with epoll
        var event = epoll_event()
        event.events = LinuxCompat.EPOLLIN | LinuxCompat.EPOLLET
        event.data.fd = self.eventFd
        
        let result = epoll_ctl(self.epollFd, LinuxCompat.EPOLL_CTL_ADD, self.eventFd, &event)
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
        var value: UInt64 = 1
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
                // epoll_wait error - errno contains the error code
                break
            }
            
            for i in 0..<Int(nfds) {
                if events[i].data.fd == eventFd {
                    // Handle task notifications
                    handleTaskNotification()
                } else {
                    // Handle socket events
                    handleSocketEvent(fd: events[i].data.fd)
                }
            }
        }
    }
    
    private func handleTaskNotification() {
        // Clear the eventfd
        var value: UInt64 = 0
        _ = read(eventFd, &value, MemoryLayout<UInt64>.size)
        
        // Execute pending tasks
        let tasks = pendingTasks.exchangeAll([])
        for task in tasks {
            task()
        }
    }
    
    private func handleSocketEvent(fd: Int32) {
        handlersLock.withLock {
            if let handler = socketHandlers[fd] {
                handler()
            }
        }
    }
    
    /// Execute a block asynchronously on the event loop
    func execute(_ block: @escaping @Sendable () -> Void) {
        pendingTasks.append(block)
        
        // Wake up the event loop
        var value: UInt64 = 1
        _ = write(eventFd, &value, MemoryLayout<UInt64>.size)
    }
    
    /// Register a socket for monitoring
    func registerSocket(_ fd: Int32, events: UInt32, handler: @escaping () -> Void) -> Bool {
        var event = epoll_event()
        event.events = events
        event.data.fd = fd
        
        let result = epoll_ctl(epollFd, LinuxCompat.EPOLL_CTL_ADD, fd, &event)
        if result == 0 {
            handlersLock.withLock {
                socketHandlers[fd] = handler
            }
            return true
        }
        return false
    }
    
    /// Unregister a socket from monitoring
    func unregisterSocket(_ fd: Int32) {
        _ = epoll_ctl(epollFd, LinuxCompat.EPOLL_CTL_DEL, fd, nil)
        _ = handlersLock.withLock {
            socketHandlers.removeValue(forKey: fd)
        }
    }
    
    /// Modify socket monitoring events
    func modifySocket(_ fd: Int32, events: UInt32) -> Bool {
        var event = epoll_event()
        event.events = events
        event.data.fd = fd
        
        let result = epoll_ctl(epollFd, LinuxCompat.EPOLL_CTL_MOD, fd, &event)
        return result == 0
    }
}

// MARK: - Thread-safe utilities for Linux

/// Thread-safe boolean for Linux
private final class AtomicBool: @unchecked Sendable {
    private var value: Bool
    private let lock = ThreadLock()
    
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

/// Thread-safe array for Linux
private final class AtomicArray<T>: @unchecked Sendable {
    private var array: [T] = []
    private let lock = ThreadLock()
    
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

/// Platform-agnostic thread lock
private final class ThreadLock: @unchecked Sendable {
    #if canImport(Musl)
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
    
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        return try body()
    }
    #else
    private let lock = NSLock()
    
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
    #endif
}

#endif