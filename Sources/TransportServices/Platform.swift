//
//  Platform.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

internal protocol Platform {
    func initiate(preconnection: Preconnection, eventHandler: @escaping (TransportServicesEvent) -> Void) -> Connection
    func listen(preconnection: Preconnection, eventHandler: @escaping (TransportServicesEvent) -> Void) -> Listener
    func rendezvous(preconnection: Preconnection, eventHandler: @escaping (TransportServicesEvent) -> Void)
}
