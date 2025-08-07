//
//  AppleListener.swift
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

/// Apple platform-specific listener implementation using Network.framework
public final class AppleListener: Listener, @unchecked Sendable {
    public let preconnection: Preconnection
    public let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    private let nwListener: NWListener
    private var pendingConnections: [NWConnection] = []
    private let connectionQueue = DispatchQueue(label: "listener.connections")
    private var isListening = false
    private var acceptTask: Task<Void, Never>?
    private var _newConnectionLimit: UInt?
    private var acceptedConnections: UInt = 0
    
    init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) throws {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        
        // Create NWParameters based on preconnection properties
        let parameters = AppleListener.createParameters(from: preconnection)
        
        // Create listener with appropriate port
        guard let localEndpoint = preconnection.localEndpoints.first else {
            throw TransportServicesError.invalidConfiguration
        }
        
        let port: NWEndpoint.Port
        if let specifiedPort = localEndpoint.port {
            port = NWEndpoint.Port(rawValue: specifiedPort) ?? .any
        } else {
            port = .any
        }
        
        guard let listener = try? NWListener(using: parameters, on: port) else {
            throw TransportServicesError.establishmentFailed(reason: "Failed to create listener")
        }
        
        self.nwListener = listener
    }
    
    private func setupHandlers() {
        nwListener.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            
            Task {
                self.handleStateUpdate(newState)
            }
        }
        
        nwListener.newConnectionHandler = { [weak self] nwConnection in
            guard let self = self else { return }
            
            Task {
                self.addPendingConnection(nwConnection)
            }
        }
    }
    
    private func handleStateUpdate(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            self.isListening = true
        case .failed(_), .cancelled:
            self.isListening = false
        default:
            break
        }
    }
    
    private func addPendingConnection(_ connection: NWConnection) {
        pendingConnections.append(connection)
    }
    
    public func listen() async throws {
        // Setup handlers before starting
        setupHandlers()
        
        nwListener.start(queue: .global())
        
        // Wait for listener to be ready
        try await withCheckedThrowingContinuation { continuation in
            let checkState = {
                if self.isListening {
                    continuation.resume()
                } else if case .failed(let error) = self.nwListener.state {
                    continuation.resume(throwing: error)
                }
            }
            
            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .ready:
                    Task {
                        self.handleStateUpdate(state)
                        self.setupHandlers() // Re-setup normal handlers
                    }
                    continuation.resume()
                case .failed(let error):
                    Task {
                        self.handleStateUpdate(state)
                    }
                    continuation.resume(throwing: error)
                default:
                    Task {
                        self.handleStateUpdate(state)
                    }
                }
            }
            
            checkState()
        }
        
        // Start accepting connections in the background
        acceptTask = Task {
            await acceptLoop()
        }
    }
    
    public func stop() async {
        guard isListening else { return }
        
        isListening = false
        acceptTask?.cancel()
        nwListener.cancel()
        eventHandler(.stopped(self))
    }
    
    public func accept() async throws -> any Connection {
        guard isListening else {
            throw TransportServicesError.connectionClosed
        }
        
        // Wait for a pending connection
        while true {
            if !pendingConnections.isEmpty {
                let nwConnection = pendingConnections.removeFirst()
                
                // Create a new AppleConnection wrapper
                let appleConnection = AppleConnection(
                    nwConnection: nwConnection,
                    preconnection: preconnection,
                    eventHandler: eventHandler
                )
                
                // The connection is already being established by Network.framework
                nwConnection.start(queue: .global())
                
                return appleConnection
            }
            
            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    /// Accept incoming connections in a loop
    private func acceptLoop() async {
        while isListening && !Task.isCancelled {
            // Check connection limit
            if let limit = await newConnectionLimit, acceptedConnections >= limit {
                // Stop accepting new connections
                break
            }
            
            do {
                // Accept a new connection
                let connection = try await accept()
                acceptedConnections += 1
                
                // Deliver connection to application
                eventHandler(.connectionReceived(self, connection))
                
                // Start receiving on the connection if bidirectional
                if preconnection.transportProperties.direction != .unidirectionalSend {
                    Task {
                        await connection.startReceiving()
                    }
                }
                
            } catch {
                // If we get an error, it might mean the listener was stopped
                // or there was a network error
                if isListening {
                    // Error accepting connection - continue listening
                }
            }
        }
        
        // If we exited the loop due to connection limit, keep the listener active
        // but stop accepting new connections
        if let limit = await newConnectionLimit, acceptedConnections >= limit {
            // Connection limit reached
        }
    }
    
    // MARK: - Listener Protocol Implementation
    
    public func setNewConnectionLimit(_ value: UInt?) async {
        self._newConnectionLimit = value
    }
    
    public var newConnectionLimit: UInt? {
        get async {
            return _newConnectionLimit
        }
    }
    
    public var acceptedConnectionCount: UInt {
        get async {
            return acceptedConnections
        }
    }
    
    public var properties: TransportProperties {
        get async {
            return preconnection.transportProperties
        }
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
        // Check if any security parameters are configured
        if preconnection.securityParameters.allowedSecurityProtocols != nil ||
           preconnection.securityParameters.serverCertificate != nil ||
           preconnection.securityParameters.clientCertificate != nil {
            let tlsOptions = NWProtocolTLS.Options()
            parameters.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
        }
        
        return parameters
    }
}

#else

/// Stub implementation for non-Apple platforms
public final class AppleListener: Listener, @unchecked Sendable {
    public let preconnection: Preconnection
    public let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) throws {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
    }
    
    public func listen() async throws {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
    
    public func stop() async {}
    
    public func accept() async throws -> any Connection {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
    
    public func setNewConnectionLimit(_ value: UInt?) async {}
    public var newConnectionLimit: UInt? {
        get async {
            return nil
        }
    }
    public var acceptedConnectionCount: UInt {
        get async {
            return 0
        }
    }
    public var properties: TransportProperties {
        get async {
            return preconnection.transportProperties
        }
    }
}

#endif
