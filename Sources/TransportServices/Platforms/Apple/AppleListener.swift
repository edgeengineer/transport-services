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
public final class AppleListener: PlatformListener, @unchecked Sendable {
    private let nwListener: NWListener
    private let preconnection: Preconnection
    private var pendingConnections: [NWConnection] = []
    private let connectionQueue = DispatchQueue(label: "listener.connections")
    private var isListening = false
    
    init(preconnection: Preconnection) throws {
        self.preconnection = preconnection
        
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
        
        // Set up handlers
        setupHandlers()
    }
    
    private func setupHandlers() {
        nwListener.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            
            switch newState {
            case .ready:
                self.isListening = true
            case .failed(_), .cancelled:
                self.isListening = false
            default:
                break
            }
        }
        
        nwListener.newConnectionHandler = { [weak self] nwConnection in
            guard let self = self else { return }
            
            self.connectionQueue.sync {
                self.pendingConnections.append(nwConnection)
            }
        }
    }
    
    public func listen() async throws {
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
                    self.isListening = true
                    self.setupHandlers() // Re-setup normal handlers
                    continuation.resume()
                case .failed(let error):
                    self.isListening = false
                    self.setupHandlers() // Re-setup normal handlers
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            
            // Check if already ready
            checkState()
        }
    }
    
    public func stop() async {
        isListening = false
        nwListener.cancel()
    }
    
    public func accept() async throws -> any PlatformConnection {
        guard isListening else {
            throw TransportServicesError.connectionClosed
        }
        
        // Wait for a pending connection
        while true {
            let connection = connectionQueue.sync { () -> NWConnection? in
                if !pendingConnections.isEmpty {
                    return pendingConnections.removeFirst()
                }
                return nil
            }
            
            if let nwConnection = connection {
                // Create a new AppleConnection wrapper
                let appleConnection = AppleConnection(preconnection: preconnection)
                
                // The connection is already being established by Network.framework
                nwConnection.start(queue: .global())
                
                return appleConnection
            }
            
            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
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
        if preconnection.securityParameters != nil {
            let tlsOptions = NWProtocolTLS.Options()
            parameters.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
        }
        
        return parameters
    }
}

#else

/// Stub implementation for non-Apple platforms
public final class AppleListener: PlatformListener {
    public func listen() async throws {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
    
    public func stop() async {}
    
    public func accept() async throws -> any PlatformConnection {
        throw TransportServicesError.notSupported(reason: "Apple Network.framework not available")
    }
}

#endif