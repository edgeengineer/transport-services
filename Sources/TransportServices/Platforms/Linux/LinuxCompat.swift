//
//  LinuxCompat.swift
//  
//
//  Maximilian Alexander
//

#if os(Linux)
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#else
#error("Unsupported C library")
#endif

/// Compatibility layer for differences between Glibc and Musl
internal struct LinuxCompat {
    
    // MARK: - Socket Constants
    
    /// Some constants might have different names or values
    #if canImport(Musl)
    // Musl-specific adjustments if needed
    static let SOCK_STREAM = Int32(1)
    static let SOCK_DGRAM = Int32(2)
    static let SOCK_NONBLOCK = Int32(2048)
    static let SOCK_CLOEXEC = Int32(524288)
    #else
    // Use raw values for Glibc - these are standard on Linux
    static let SOCK_STREAM = Int32(1)
    static let SOCK_DGRAM = Int32(2)
    static let SOCK_NONBLOCK = Int32(2048)  // O_NONBLOCK equivalent for sockets
    static let SOCK_CLOEXEC = Int32(524288) // FD_CLOEXEC equivalent for sockets
    #endif
    
    // MARK: - Epoll Constants
    
    #if canImport(Musl)
    // Musl epoll constants (usually the same as Glibc)
    static let EPOLL_CLOEXEC = Int32(0x80000)
    static let EPOLLIN: UInt32 = 0x001
    static let EPOLLOUT: UInt32 = 0x004
    static let EPOLLERR: UInt32 = 0x008
    static let EPOLLHUP: UInt32 = 0x010
    static let EPOLLET: UInt32 = 0x80000000
    static let EPOLL_CTL_ADD = Int32(1)
    static let EPOLL_CTL_DEL = Int32(2)
    static let EPOLL_CTL_MOD = Int32(3)
    #else
    // Use raw values for Glibc - these are standard on Linux
    static let EPOLL_CLOEXEC = Int32(0x80000)
    static let EPOLLIN: UInt32 = 0x001
    static let EPOLLOUT: UInt32 = 0x004
    static let EPOLLERR: UInt32 = 0x008
    static let EPOLLHUP: UInt32 = 0x010
    static let EPOLLET: UInt32 = 0x80000000
    static let EPOLL_CTL_ADD = Int32(1)
    static let EPOLL_CTL_DEL = Int32(2)
    static let EPOLL_CTL_MOD = Int32(3)
    #endif
    
    // MARK: - Event FD Constants
    
    #if canImport(Musl)
    static let EFD_CLOEXEC = Int32(0x80000)
    static let EFD_NONBLOCK = Int32(0x800)
    #else
    // Use raw values for Glibc - these are standard on Linux
    static let EFD_CLOEXEC = Int32(0x80000)
    static let EFD_NONBLOCK = Int32(0x800)
    #endif
    
    // MARK: - TCP/IP Constants
    
    #if canImport(Musl)
    static let TCP_NODELAY = Int32(1)
    static let MSG_NOSIGNAL = Int32(0x4000)
    #else
    static let TCP_NODELAY = Int32(Glibc.TCP_NODELAY)
    static let MSG_NOSIGNAL = Int32(Glibc.MSG_NOSIGNAL)
    #endif
    
    // MARK: - Helper Functions
    
    /// Thread-safe strerror wrapper
    static func errorString(_ errno: Int32) -> String {
        #if canImport(Musl)
        // Musl's strerror is thread-safe
        return String(cString: strerror(errno))
        #else
        // Use strerror_r for thread safety in Glibc
        var buffer = [CChar](repeating: 0, count: 256)
        _ = strerror_r(errno, &buffer, buffer.count)
        // Find the null terminator
        let validLength = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer[..<validLength], as: UTF8.self)
        #endif
    }
    
    /// Check if we're running on Alpine Linux (common Musl distro)
    static var isAlpineLinux: Bool {
        #if canImport(Musl)
        return true
        #else
        // Check /etc/os-release for Alpine
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/etc/os-release")),
           let content = String(data: data, encoding: .utf8),
           content.contains("Alpine") {
            return true
        }
        return false
        #endif
    }
}

// MARK: - Extension for NSLock compatibility

#if canImport(Musl)
import Foundation

// Musl might need pthread mutex directly if NSLock is not available
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
    
    func tryLock() -> Bool {
        return pthread_mutex_trylock(&mutex) == 0
    }
}

// Use MutexLock as NSLock replacement if needed
typealias PlatformLock = MutexLock
#else
import Foundation
typealias PlatformLock = NSLock
#endif

#endif // os(Linux)