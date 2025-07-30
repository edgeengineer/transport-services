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
import CIOUring

internal final class EventLoop {
    private static let singleton = EventLoop()
    private let ring: OpaquePointer
    private let thread: Thread

    private init() {
        self.ring = iouring_create(32)!
        self.thread = Thread { [weak self] in
            self?.run()
        }
        self.thread.start()
    }

    deinit {
        iouring_destroy(ring)
    }

    private func run() {
        while true {
            iouring_submit_and_wait(ring, 1)
            var cqe: UnsafeMutablePointer<io_uring_cqe>?
            io_uring_peek_cqe(ring, &cqe)
            if let cqe = cqe {
                let block = Unmanaged<() -> Void>.fromOpaque(UnsafeRawPointer(bitPattern: cqe.pointee.user_data)!).takeRetainedValue()
                block()
                iouring_cqe_seen(ring, cqe)
            }
        }
    }

    public static func execute(_ block: @escaping @Sendable () -> Void) {
        let sqe = iouring_get_sqe(singleton.ring)
        let unmanaged = Unmanaged.passRetained(block as AnyObject)
        io_uring_prep_nop(sqe)
        io_uring_sqe_set_data(sqe, UnsafeMutableRawPointer(unmanaged.toOpaque()))
    }
}
#elseif os(Windows)
internal final class EventLoop {
    // Placeholder for IOCP implementation
    public static func execute(_ block: @escaping () -> Void) {
        // For now, just execute the block directly
        block()
    }
}
#endif
