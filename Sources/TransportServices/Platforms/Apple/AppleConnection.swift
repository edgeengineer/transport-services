//
//  AppleConnection.swift
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

#if canImport(Network)
import Network

/// Apple platform-specific connection implementation using Network.framework
public final actor AppleConnection: Connection {
    public let preconnection: Preconnection
    public nonisolated let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    private let nwConnection: NWConnection
    private var _state: ConnectionState = .establishing
    private var _group: ConnectionGroup?
    private var _properties: TransportProperties
    
    public init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self._properties = preconnection.transportProperties
        
        // Create NWParameters based on preconnection properties
        let parameters = AppleConnection.createParameters(from: preconnection)
        
        // Create NWEndpoint from remote endpoint
        guard let remoteEndpoint = preconnection.remoteEndpoints.first,
              let nwEndpoint = AppleConnection.createEndpoint(from: remoteEndpoint) else {
            fatalError("No valid remote endpoint")
        }
        
        self.nwConnection = NWConnection(to: nwEndpoint, using: parameters)
    }
    
    init(nwConnection: NWConnection, preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.nwConnection = nwConnection
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self._properties = preconnection.transportProperties
    }
    
    // MARK: - Connection Protocol Implementation
    
    public var state: ConnectionState {
        _state
    }
    
    public var properties: TransportProperties {
        _properties
    }
    
    public var group: ConnectionGroup? {
        _group
    }
    
    public func setGroup(_ group: ConnectionGroup?) {
        _group = group
    }
    
    // MARK: - Connection Lifecycle
    
    public func initiate() {
        nwConnection.stateUpdateHandler = { [weak self] newState in
            Task {
                await self?.handleStateUpdate(newState)
            }
        }
        nwConnection.start(queue: .global())
    }
    
    public func close() async {
        _state = .closing
        let handler = eventHandler
        Task.detached {
            handler(.closed(self))
        }
        nwConnection.cancel()
    }
    
    nonisolated public func abort() {
        // Force cancel the connection immediately
        nwConnection.forceCancel()
        
        // Update state asynchronously
        Task {
            await self.markAborted()
        }
    }
    
    public func clone() async throws -> any Connection {
        // Create new AppleConnection with same preconnection
        let newConnection = AppleConnection(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        // Copy connection group membership
        if let group = _group {
            await group.addConnection(newConnection)
            await newConnection.setGroup(group)
        }
        
        // Initiate the cloned connection
        await newConnection.initiate()
        
        return newConnection
    }
    
    // MARK: - Data Transfer
    
    public func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        guard state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nwConnection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        eventHandler(.sent(self, context))
    }
    
    public func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext) {
        guard state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, MessageContext, Bool), Error>) in
            nwConnection.receive(minimumIncompleteLength: minIncompleteLength ?? 1,
                                maximumLength: maxLength ?? 65536) { content, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = content {
                    let context = MessageContext()
                    continuation.resume(returning: (data, context, isComplete))
                } else {
                    continuation.resume(throwing: TransportServicesError.connectionClosed)
                }
            }
        }
        
        let (data, context, endOfMessage) = result
        
        if endOfMessage {
            eventHandler(.received(self, data, context))
        } else {
            eventHandler(.receivedPartial(self, data, context, endOfMessage: false))
        }
        
        return (data, context)
    }
    
    public func startReceiving(minIncompleteLength: Int?, maxLength: Int?) {
        Task {
            while state == .established {
                do {
                    let _ = try await receive(
                        minIncompleteLength: minIncompleteLength,
                        maxLength: maxLength
                    )
                } catch {
                    // Connection closed or error occurred
                    break
                }
            }
        }
    }
    
    // MARK: - Endpoint Management
    
    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    public func removeRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    public func addLocal(_ localEndpoints: [LocalEndpoint]) {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    public func removeLocal(_ localEndpoints: [LocalEndpoint]) {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    // MARK: - Private Methods
    
    private func handleStateUpdate(_ newState: NWConnection.State) async {
        switch newState {
        case .ready:
            self._state = .established
            eventHandler(.ready(self))
        case .failed(let error):
            self._state = .closed
            eventHandler(.connectionError(self, reason: error.localizedDescription))
        case .cancelled:
            self._state = .closed
            eventHandler(.closed(self))
        case .waiting(let error):
            eventHandler(.connectionError(self, reason: error.localizedDescription))
        case .preparing:
            self._state = .establishing
        case .setup:
            self._state = .establishing
        @unknown default:
            break
        }
    }
    
    private func markAborted() {
        _state = .closed
        eventHandler(.connectionError(self, reason: "Connection aborted"))
    }
    
    // MARK: - Helper Methods
    
    private static func createParameters(from preconnection: Preconnection) -> NWParameters {
        let properties = preconnection.transportProperties
        
        // Determine protocol based on properties
        let parameters: NWParameters
        
        if properties.reliability == .require {
            parameters = .tcp
        } else {
            parameters = .udp
        }
        
        // Configure TLS if security is enabled
        if preconnection.securityParameters != nil {
            let tlsOptions = NWProtocolTLS.Options()
            parameters.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
        }
        
        // Configure multipath
        if properties.multipath != .disabled {
            parameters.multipathServiceType = .aggregate
        }
        
        return parameters
    }
    
    private static func createEndpoint(from remoteEndpoint: RemoteEndpoint) -> NWEndpoint? {
        if let hostName = remoteEndpoint.hostName,
           let port = remoteEndpoint.port {
            return NWEndpoint.hostPort(host: NWEndpoint.Host(hostName),
                                      port: NWEndpoint.Port(rawValue: port) ?? 443)
        } else if let ipAddress = remoteEndpoint.ipAddress,
                  let port = remoteEndpoint.port {
            return NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress),
                                      port: NWEndpoint.Port(rawValue: port) ?? 443)
        }
        return nil
    }
}

#endif