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

#if canImport(Synchronization)
import Synchronization
#endif

/// Apple platform-specific connection implementation using Network.framework
public final class AppleConnection: Connection, @unchecked Sendable {
    public let preconnection: Preconnection
    public let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    private let nwConnection: NWConnection
    #if canImport(Synchronization)
    private let stateLock = Mutex<Void>(())
    #else
    private let stateLock = NSLock()
    #endif
    private var _state: ConnectionState = .establishing
    public var state: ConnectionState {
        get async {
            #if canImport(Synchronization)
            return stateLock.withLock { _ in _state }
            #else
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
            #endif
        }
    }
    private var _group: ConnectionGroup?
    public var group: ConnectionGroup? {
        get async {
            #if canImport(Synchronization)
            return stateLock.withLock { _ in _group }
            #else
            stateLock.lock()
            defer { stateLock.unlock() }
            return _group
            #endif
        }
    }
    private var _properties: TransportProperties
    public var properties: TransportProperties {
        get async {
            #if canImport(Synchronization)
            return stateLock.withLock { _ in _properties }
            #else
            stateLock.lock()
            defer { stateLock.unlock() }
            return _properties
            #endif
        }
    }
    
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
    

    
    public func setGroup(_ group: ConnectionGroup?) async {
        #if canImport(Synchronization)
        stateLock.withLock { _ in
            self._group = group
        }
        #else
        stateLock.lock()
        defer { stateLock.unlock() }
        self._group = group
        #endif
    }
    
    // MARK: - Connection Lifecycle
    
    public func initiate() async {
        nwConnection.stateUpdateHandler = { [weak self] newState in
            self?.handleStateUpdate(newState)
        }
        nwConnection.start(queue: .global())
    }
    
    public func close() async {
        #if canImport(Synchronization)
        stateLock.withLock { _ in _state = .closing }
        #else
        stateLock.lock()
        _state = .closing
        stateLock.unlock()
        #endif
        
        nwConnection.cancel()
        eventHandler(.closed(self))
    }
    
    public func abort() async {
        #if canImport(Synchronization)
        stateLock.withLock { _ in _state = .closed }
        #else
        stateLock.lock()
        _state = .closed
        stateLock.unlock()
        #endif
        
        // Force cancel the connection immediately
        nwConnection.forceCancel()
        eventHandler(.connectionError(self, reason: "Connection aborted"))
    }
    
    public func clone() async throws -> any Connection {
        // Create new AppleConnection with same preconnection
        let newConnection = AppleConnection(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        // Copy connection group membership
        if let group = await self.group {
             await group.addConnection(newConnection)
             await newConnection.setGroup(group)
         }
        
        // Initiate the cloned connection
        await newConnection.initiate()
        
        return newConnection
    }
    
    // MARK: - Data Transfer
    
    public func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        let currentState = await state
        guard currentState == .established else {
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
        let currentState = await state
        guard currentState == .established else {
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
    
    public func startReceiving(minIncompleteLength: Int?, maxLength: Int?) async {
        Task {
            while await state == .established {
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
    
    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) async {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    public func removeRemote(_ remoteEndpoints: [RemoteEndpoint]) async {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    public func addLocal(_ localEndpoints: [LocalEndpoint]) async {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    public func removeLocal(_ localEndpoints: [LocalEndpoint]) async {
        // This would be implemented by Network.framework for multipath
        // For now, this is a placeholder
    }
    
    // MARK: - Private Methods
    
    private func handleStateUpdate(_ newState: NWConnection.State) {
        #if canImport(Synchronization)
        stateLock.withLock { _ in
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
        #else
        stateLock.lock()
        defer { stateLock.unlock() }
        
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
        #endif
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