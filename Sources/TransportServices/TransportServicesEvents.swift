//
//  TapsEvents.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

public enum TransportServicesEvent {
    case ready(Connection)
    case connectionReceived(Listener, Connection)
    case rendezvousDone(Preconnection, Connection)
    case establishmentError(reason: String?)
    case connectionError(Connection, reason: String?)
    case closed(Connection)
    case stopped(Listener)
    case sent(Connection, MessageContext)
    case expired(Connection, MessageContext)
    case sendError(Connection, MessageContext, reason: String?)
    case received(Connection, Data, MessageContext)
    case receivedPartial(Connection, Data, MessageContext, endOfMessage: Bool)
    case receiveError(Connection, MessageContext, reason: String?)
    case softError(Connection, reason: String?)
    case pathChange(Connection)
    case cloneError(Connection, reason: String?)
}
