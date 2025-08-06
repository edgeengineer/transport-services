//
//  TransportServicesEvents.swift
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

public enum TransportServicesEvent: Sendable {
    case ready(any Connection)
    case connectionReceived(any Listener, any Connection)
    case rendezvousDone(Preconnection, any Connection)
    case establishmentError(reason: String?)
    case connectionError(any Connection, reason: String?)
    case closed(any Connection)
    case stopped(any Listener)
    case sent(any Connection, MessageContext)
    case expired(any Connection, MessageContext)
    case sendError(any Connection, MessageContext, reason: String?)
    case received(any Connection, Data, MessageContext)
    case receivedPartial(any Connection, Data, MessageContext, endOfMessage: Bool)
    case receiveError(any Connection, MessageContext, reason: String?)
    case softError(any Connection, reason: String?)
    case pathChange(any Connection)
    case cloneError(any Connection, reason: String?)
}
