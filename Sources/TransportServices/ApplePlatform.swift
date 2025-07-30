//
//  ApplePlatform.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation
import Network

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
internal class ApplePlatform: Platform {
    func initiate(preconnection: Preconnection, eventHandler: @escaping (TransportServicesEvent) -> Void) -> Connection {
        let connection = Connection(preconnection: preconnection)
        // Placeholder for Network.framework implementation
        return connection
    }

    func listen(preconnection: Preconnection, eventHandler: @escaping (TransportServicesEvent) -> Void) -> Listener {
        let listener = Listener(preconnection: preconnection)
        // Placeholder for Network.framework implementation
        return listener
    }

    func rendezvous(preconnection: Preconnection, eventHandler: @escaping (TransportServicesEvent) -> Void) {
        // Placeholder for Network.framework implementation
    }
}
#endif
