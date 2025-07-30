//
//  Taps.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

public actor Taps {
    public typealias EventHandler = (TransportServicesEvent) -> Void
    private let platform: Platform

    public init() {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        self.platform = ApplePlatform()
        #elseif os(Linux)
        self.platform = LinuxPlatform()
        #elseif os(Windows)
        self.platform = WindowsPlatform()
        #else
        fatalError("Unsupported platform")
        #endif
    }

    public func initiate(preconnection: Preconnection, timeout: TimeInterval? = nil, eventHandler: @escaping EventHandler) -> Connection {
        let connection = Connection(preconnection: preconnection, eventHandler: eventHandler)
        // The platform-specific implementation will be called here
        // to start the connection process.
        return connection
    }

        // The platform-specific implementation will be called here
        // to start the connection process.
        return connection
    }

    public func listen(preconnection: Preconnection) -> Listener {
        let listener = Listener(preconnection: preconnection)
        // The platform-specific implementation will be called here
        // to start the listening process.
        return listener
    }

    public func rendezvous(preconnection: Preconnection) {
        // The platform-specific implementation will be called here
        // to start the rendezvous process.
    }
}
