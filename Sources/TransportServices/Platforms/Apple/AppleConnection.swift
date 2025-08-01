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
public final actor AppleConnection: PlatformConnection {
    private let nwConnection: NWConnection
    private let preconnection: Preconnection
    
    private var ownerConnection: Connection?
    private var state: ConnectionState = .establishing
    
    
    init(preconnection: Preconnection) {
        self.preconnection = preconnection
        
        // Create NWParameters based on preconnection properties
        let parameters = AppleConnection.createParameters(from: preconnection)
        
        // Create NWEndpoint from remote endpoint
        guard let remoteEndpoint = preconnection.remoteEndpoints.first,
              let nwEndpoint = AppleConnection.createEndpoint(from: remoteEndpoint) else {
            fatalError("No valid remote endpoint")
        }
        
        self.nwConnection = NWConnection(to: nwEndpoint, using: parameters)
        
        // Set up state update handler
        Task { await setupStateHandler() }
    }

    init(nwConnection: NWConnection, preconnection: Preconnection) {
        self.nwConnection = nwConnection
        self.preconnection = preconnection
        
        // Set up state update handler
        Task { await setupStateHandler() }
    }
    
    private func setupStateHandler() {
        nwConnection.stateUpdateHandler = { [weak self] newState in
            Task {
                await self?.handleStateUpdate(newState)
            }
        }
    }

    private func handleStateUpdate(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            self.state = .established
            if let owner = self.ownerConnection {
                Task { await owner.updateState(.established) }
                owner.eventHandler(.ready(owner))
            }
        case .failed(_), .cancelled:
            self.state = .closed
            if let owner = self.ownerConnection {
                Task { await owner.updateState(.closed) }
                owner.eventHandler(.closed(owner))
            }
        default:
            break
        }
    }
    
    public func initiate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nwConnection.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .ready:
                    Task {
                        await self.handleStateUpdate(newState)
                        continuation.resume()
                    }
                case .failed(let error):
                    Task {
                        await self.handleStateUpdate(newState)
                        continuation.resume(throwing: error)
                    }
                default:
                    Task { await self.handleStateUpdate(newState) }
                }
            }
            nwConnection.start(queue: .global())
        }
    }
    
    public func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        guard await getState() == .established else {
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
    }
    
    public func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext, Bool) {
        guard await getState() == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
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
    }
    
    public func close() async {
        state = .closing
        if let owner = self.ownerConnection {
            Task { await owner.updateState(.closing) }
        }

        nwConnection.cancel()
    }
    
    public func abort() async {
        state = .closed
        if let owner = self.ownerConnection {
            Task { await owner.updateState(.closed) }
            owner.eventHandler(.connectionError(owner, reason: "aborted"))
        }
        
        nwConnection.forceCancel()
    }
    
    public func getState() async -> ConnectionState {
        return state
    }
    
    
    
    public func setOwnerConnection(_ connection: Connection?) async {
        self.ownerConnection = connection
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

#else

/// Stub implementation for non-Apple platforms
public final class AppleConnection: PlatformConnection {
    public func initiate() async throws {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
    
    public func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
    
    public func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext, Bool) {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
    
    public func close() async {}
    
    public func abort() async {}
    
    public func getState() async -> ConnectionState { .closed }
    
    
    
    public func setOwnerConnection(_ connection: Connection?) async {}
}

#endif