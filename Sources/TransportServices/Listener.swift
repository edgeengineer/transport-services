//
//  Listener.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

public actor Listener {
    public let preconnection: Preconnection
    private var newConnectionLimit: UInt?

    public init(preconnection: Preconnection) {
        self.preconnection = preconnection
    }

    public func start() {
        // Placeholder for implementation
    }

    public func stop() {
        // Placeholder for implementation
    }

    public func setNewConnectionLimit(_ value: UInt?) {
        self.newConnectionLimit = value
    }
}
