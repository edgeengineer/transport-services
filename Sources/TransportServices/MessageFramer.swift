//
//  MessageFramer.swift
//  
//
//  Created by Cline on 7/30/25.
//

import Foundation

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol MessageFramer {
    func start(connection: Connection)
    func stop(connection: Connection)
    func makeConnectionReady(connection: Connection)
    func makeConnectionClosed(connection: Connection)
    func failConnection(connection: Connection, error: Error)
    func prependFramer(connection: Connection, framer: MessageFramer)
    func startPassthrough()
    func newSentMessage(connection: Connection, messageData: Data, messageContext: MessageContext, endOfMessage: Bool)
    func send(connection: Connection, messageData: Data)
    func handleReceivedData(connection: Connection)
    func parse(connection: Connection, minimumIncompleteLength: Int, maximumLength: Int) -> (Data, MessageContext, Bool)
    func advanceReceiveCursor(connection: Connection, length: Int)
    func deliverAndAdvanceReceiveCursor(connection: Connection, messageContext: MessageContext, length: Int, endOfMessage: Bool)
    func deliver(connection: Connection, messageContext: MessageContext, messageData: Data, endOfMessage: Bool)
}
