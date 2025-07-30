//
//  LinuxPlatform.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

#if os(Linux)
internal class LinuxPlatform: Platform {
    func initiate(preconnection: Preconnection, eventHandler: @escaping (TapsEvent) -> Void) -> Connection {
        let connection = Connection(preconnection: preconnection)
        // Placeholder for io_uring implementation
        return connection
    }

    func listen(preconnection: Preconnection, eventHandler: @escaping (TapsEvent) -> Void) -> Listener {
        let listener = Listener(preconnection: preconnection)
        // Placeholder for io_uring implementation
        return listener
    }

    func rendezvous(preconnection: Preconnection, eventHandler: @escaping (TapsEvent) -> Void) {
        // Placeholder for io_uring implementation
    }
}
#endif
