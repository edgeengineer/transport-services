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

/// Apple platform connection implementation
actor AppleConnection: @preconcurrency PlatformConnection {
    private let preconnection: Preconnection
    private let eventHandler: @Sendable (TransportServicesEvent) -> Void
    internal var nwConnection: NWConnection?
    private let queue = DispatchQueue(label: "apple.connection")
    private var state: ConnectionState = .establishing
    
    // Connection properties
    private var connectionProperties: [String: Any] = [:]
    
    // Group management
    private weak var connectionGroup: AppleConnectionGroup?
    
    // Path monitoring
    private var pathUpdateHandler: ((NWPath) -> Void)?
    
    // Owner connection reference for proper event handling
    private weak var ownerConnection: Connection?
    
    init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void, nwConnection: NWConnection? = nil) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self.nwConnection = nwConnection
        
        // Initialize connection properties from preconnection
        Task {
            await initializeConnectionProperties()
        }
    }
    
    func setOwnerConnection(_ connection: Connection?) async {
        self.ownerConnection = connection
    }
    
    private func updateState(_ newState: ConnectionState) {
        let oldState = self.state
        self.state = newState
        
        // Handle state transitions according to RFC 9622 Section 11
        // Fire events through the owner connection if available
        if let owner = ownerConnection {
            Task {
                await owner.updateState(newState)
            }
            
            // Fire appropriate events based on state transitions
            switch (oldState, newState) {
            case (.establishing, .established):
                eventHandler(.ready(owner))
            case (_, .closed):
                eventHandler(.closed(owner))
            default:
                break
            }
        }
    }
    
    private func initializeConnectionProperties() {
        // Initialize from transport properties
        let properties = preconnection.transportProperties
        
        // Connection priority (Section 8.1.2)
        connectionProperties["connPriority"] = 100
        
        // Timeout properties (Section 8.1.3, 8.1.4)
        connectionProperties["connTimeout"] = nil // Disabled by default
        connectionProperties["keepAliveTimeout"] = nil // Disabled by default
        
        // Multipath policy (Section 8.1.7)
        if properties.multipath != .disabled {
            connectionProperties["multipathPolicy"] = properties.multipathPolicy
        }
        
        // Capacity profile (Section 8.1.6)
        connectionProperties["connCapacityProfile"] = "default"
    }
    
    func initiate() async throws {
        // Convert preconnection properties to NWParameters
        let params = createNWParameters()
        
        // Select remote endpoint - for now, use the first one
        guard let remoteEndpoint = preconnection.remoteEndpoints.first else {
            throw TransportError.noRemoteEndpoint
        }
        
        // Create NWEndpoint
        let endpoint = try createNWEndpoint(from: remoteEndpoint)
        
        // Create connection
        let connection = NWConnection(to: endpoint, using: params)
        self.nwConnection = connection
        
        // Set up handlers
        setupConnectionHandlers(connection)
        
        // Start connection with timeout support
        let timeout: TimeInterval? = nil // TODO: Add timeout support to preconnection
        
        // Set up state handler and wait for connection
        let connectionReady = AsyncStream<Result<Void, Error>> { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                Task {
                    switch state {
                    case .ready:
                        await self?.updateState(.established)
                        continuation.yield(.success(()))
                        continuation.finish()
                        
                    case .failed(let error):
                        await self?.updateState(.closed)
                        continuation.yield(.failure(error))
                        continuation.finish()
                        
                    case .waiting(let error):
                        // Handle waiting state (e.g., network not available)
                        await self?.handleWaitingState(error)
                        
                    default:
                        break
                    }
                }
            }
            
            connection.start(queue: queue)
            
            // Set up timeout if specified
            if let timeout = timeout {
                Task {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    continuation.yield(.failure(TransportError.establishmentTimeout))
                    continuation.finish()
                }
            }
        }
        
        // Wait for connection to be ready
        for await result in connectionReady {
            switch result {
            case .success:
                // Connection is ready, state should already be updated
                return
            case .failure(let error):
                throw error
            }
        }
        
        // This should not be reached as the stream should complete
        throw TransportError.establishmentFailed
    }
    
    private func setupConnectionHandlers(_ connection: NWConnection) {
        // Path update handler for multipath support
        connection.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handlePathUpdate(path)
            }
        }
        
        // Better path update handler
        connection.betterPathUpdateHandler = { [weak self] available in
            Task {
                await self?.handleBetterPathAvailable(available)
            }
        }
        
        // Viability change handler
        connection.viabilityUpdateHandler = { [weak self] viable in
            Task {
                await self?.handleViabilityChange(viable)
            }
        }
    }
    
    private func handleWaitingState(_ error: NWError) {
        // Notify application about soft errors
        if let owner = ownerConnection {
            eventHandler(.softError(owner, reason: error.localizedDescription))
        }
    }
    
    private func handlePathUpdate(_ path: NWPath) {
        // Notify about path changes (RFC 9622 Section 8.3.2)
        if let owner = ownerConnection {
            eventHandler(.pathChange(owner))
        }
        pathUpdateHandler?(path)
    }
    
    private func handleBetterPathAvailable(_ available: Bool) {
        if available && connectionProperties["multipathPolicy"] as? MultipathPolicy == .handover {
            // Consider migrating to better path
            // Note: path change events should include Connection reference
        }
    }
    
    private func handleViabilityChange(_ viable: Bool) {
        if !viable {
            // Connection viability changed
            // Note: soft errors should include Connection reference
        }
    }
    
    func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        guard let connection = nwConnection else {
            throw TransportError.notConnected
        }
        
        guard state == .established else {
            throw TransportError.notConnected
        }
        
        // Check if we can send (Section 8.1.11.2)
        if !canSend() {
            throw TransportError.cannotSend
        }
        
        // Apply message properties from context
        let metadata = createMetadataFromContext(context)
        
        // Create content context for the message
        let content = NWConnection.ContentContext(
            identifier: "message",
            metadata: metadata
        )
        
        // Handle message properties
        // Note: NWConnection.ContentContext properties are immutable after creation
        // These would need to be handled at the protocol level
        
        // Send with appropriate completion handling
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: content, isComplete: endOfMessage, completion: .contentProcessed { error in
                Task { [weak self] in
                    if let error = error {
                        if let owner = await self?.ownerConnection {
                            await self?.eventHandler(.sendError(owner, context, reason: error.localizedDescription))
                        }
                        continuation.resume(throwing: error)
                    } else {
                        if let owner = await self?.ownerConnection {
                            await self?.eventHandler(.sent(owner, context))
                        }
                        continuation.resume()
                    }
                }
            })
        }
    }
    
    private func createMetadataFromContext(_ context: MessageContext) -> [NWProtocolMetadata] {
        let metadata: [NWProtocolMetadata] = []
        
        // Handle protocol-specific metadata
        if context.priority != 100 {
            // Priority could map to service class or other protocol-specific options
            // Note: NWProtocolMetadata cannot be directly instantiated
        }
        
        // Handle no fragmentation property
        if context.noFragmentation {
            // Note: IP options need to be set at connection creation time
        }
        
        return metadata
    }
    
    private func canSend() -> Bool {
        // Check direction property
        if preconnection.transportProperties.direction == .unidirectionalReceive {
            return false
        }
        
        // Check if final message was already sent
        if connectionProperties["finalMessageSent"] as? Bool == true {
            return false
        }
        
        return state == .established
    }
    
    func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext, Bool) {
        guard let connection = nwConnection else {
            throw TransportError.notConnected
        }
        
        guard state == .established else {
            throw TransportError.notConnected
        }
        
        // Check if we can receive (Section 8.1.11.3)
        if !canReceive() {
            throw TransportError.cannotReceive
        }
        
        let minLength = minIncompleteLength ?? 1
        let maxLength = maxLength ?? 65536
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: minLength, maximumLength: maxLength) { data, contentContext, isComplete, error in
                Task { [weak self] in
                    if let error = error {
                        if let owner = await self?.ownerConnection {
                            let context = MessageContext()
                            await self?.eventHandler(.receiveError(owner, context, reason: error.localizedDescription))
                        }
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        let messageContext = await self?.createMessageContextFromReceive(contentContext: contentContext) ?? MessageContext()
                        
                        // Check if this is a final message
                        if contentContext?.isFinal == true {
                            // Mark in our connection properties
                            await self?.setConnectionProperty("finalMessageReceived", value: true)
                        }
                        
                        // Fire appropriate receive event
                        if let owner = await self?.ownerConnection {
                            if isComplete {
                                await self?.eventHandler(.received(owner, data, messageContext))
                            } else {
                                await self?.eventHandler(.receivedPartial(owner, data, messageContext, endOfMessage: isComplete))
                            }
                        }
                        
                        continuation.resume(returning: (data, messageContext, isComplete))
                    } else {
                        continuation.resume(throwing: TransportError.connectionClosed)
                    }
                }
            }
        }
    }
    
    private func createMessageContextFromReceive(contentContext: NWConnection.ContentContext?) async -> MessageContext {
        let messageContext = MessageContext()
        
        if let contentContext = contentContext {
            // Extract metadata
            for metadata in contentContext.protocolMetadata {
                if metadata is NWProtocolTCP.Metadata {
                    // Extract TCP-specific information if needed
                }
                
                if metadata is NWProtocolTLS.Metadata {
                    // Check for early data (Section 9.3.3.2)
                    // Note: earlyDataAccepted is not available in current API
                }
            }
            
            // Check if final
            if contentContext.isFinal {
                // Note: MessageContext isFinal is read-only
                // This would need to be handled at a higher level
            }
        }
        
        // Note: MessageContext endpoints are read-only and set at higher level
        
        return messageContext
    }
    
    private func canReceive() -> Bool {
        // Check direction property
        if preconnection.transportProperties.direction == .unidirectionalSend {
            return false
        }
        
        // Check if final message was already received
        if connectionProperties["finalMessageReceived"] as? Bool == true {
            return false
        }
        
        return state == .established
    }
    
    private func extractRemoteEndpoint(from connection: NWConnection) -> RemoteEndpoint? {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return nil }
        return convertNWEndpointToRemoteEndpoint(endpoint)
    }
    
    private func extractLocalEndpoint(from connection: NWConnection) -> LocalEndpoint? {
        guard let endpoint = connection.currentPath?.localEndpoint else { return nil }
        return convertNWEndpointToLocalEndpoint(endpoint)
    }
    
    func close() async {
        guard let connection = nwConnection else { return }
        
        // Graceful close - wait for outstanding data to be sent
        updateState(.closing)
        
        // Cancel the connection gracefully
        connection.cancel()
        
        // Wait for the connection to fully close
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { [weak self] state in
                if case .cancelled = state {
                    Task {
                        await self?.updateState(.closed)
                        // Note: closed event needs Connection reference
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func abort() {
        guard let connection = nwConnection else { return }
        
        // Immediate termination without waiting for outstanding data
        connection.forceCancel()
        updateState(.closed)
        
        // Send connection error event
        if let owner = ownerConnection {
            eventHandler(.connectionError(owner, reason: "Connection aborted"))
        }
    }
    
    // Support for Connection Groups (Section 7.4)
    func clone(framer: MessageFramer?, connectionProperties: TransportProperties?) async throws -> any PlatformConnection {
        guard nwConnection != nil else {
            throw TransportError.notConnected
        }
        
        // For multistream protocols like QUIC, create a new stream
        // For now, create a new connection with shared properties
        var clonedPreconnection = preconnection
        if let connectionProperties = connectionProperties {
            // Override specific properties for the clone
            clonedPreconnection.transportProperties = connectionProperties
        }
        
        let clonedConnection = AppleConnection(
            preconnection: clonedPreconnection,
            eventHandler: eventHandler
        )
        
        // Set up connection group relationship
        if let group = self.connectionGroup {
            await clonedConnection.setConnectionGroup(group)
        } else {
            // Create new connection group
            let group = AppleConnectionGroup()
            await self.setConnectionGroup(group)
            await clonedConnection.setConnectionGroup(group)
        }
        
        // Initiate the cloned connection
        try await clonedConnection.initiate()
        
        return clonedConnection
    }
    
    func setConnectionGroup(_ group: AppleConnectionGroup) {
        self.connectionGroup = group
        group.addConnection(self)
    }
    
    // Support for adding/removing endpoints (Section 7.5)
    func addRemoteEndpoints(_ endpoints: [RemoteEndpoint]) async throws {
        // For multipath connections, this would add new paths
        // Network.framework handles this automatically for multipath TCP
        // Note: path change events need Connection reference
    }
    
    func removeRemoteEndpoints(_ endpoints: [RemoteEndpoint]) async throws {
        // Remove paths if multipath is supported
        // Note: path change events need Connection reference
    }
    
    func getState() -> ConnectionState {
        return state
    }
    
    func setProperty(_ property: ConnectionProperty, value: Any) async throws {
        setConnectionProperty(property.key, value: value)
        
        // For connection group properties, propagate to all connections in the group
        // Note: Group property propagation would require more careful handling of Sendable
    }
    
    func getProperty(_ property: ConnectionProperty) async -> Any? {
        return getConnectionProperty(property.key)
    }
    
    private func setConnectionProperty(_ key: String, value: Any) {
        connectionProperties[key] = value
        
        // Apply property changes if possible
        switch key {
        case "connPriority":
            // Connection priority affects scheduling within a group
            if let priority = value as? Int {
                connectionProperties["connPriority"] = priority
            }
            
        case "connTimeout":
            // Store for monitoring connection health
            connectionProperties["connTimeout"] = value
            
        case "keepAliveTimeout":
            // Configure keep-alive if supported
            if let timeout = value as? TimeInterval,
               let connection = nwConnection,
               let tcpOptions = connection.parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.enableKeepalive = true
                tcpOptions.keepaliveInterval = Int(timeout)
            }
            
        case "connCapacityProfile":
            // Map to service class
            if let profile = value as? String,
               let connection = nwConnection {
                updateServiceClass(for: connection, profile: profile)
            }
            
        default:
            break
        }
    }
    
    private func getConnectionProperty(_ key: String) -> Any? {
        // Handle read-only properties
        switch key {
        case "connState":
            return state
            
        case "canSend":
            return canSend()
            
        case "canReceive":
            return canReceive()
            
        case "singularTransmissionMsgMaxLen":
            // Return MTU if available
            // Note: MTU is not directly available from NWPath
            return 1500 // Default MTU
            
        case "sendMsgMaxLen", "recvMsgMaxLen":
            // For message-based protocols, return appropriate limits
            return 65536 // Default max for most protocols
            
        default:
            return connectionProperties[key]
        }
    }
    
    private func updateServiceClass(for connection: NWConnection, profile: String) {
        let serviceClass: NWParameters.ServiceClass
        
        switch profile {
        case "scavenger":
            serviceClass = .background
        case "lowLatency", "interactive":
            serviceClass = .interactiveVideo
        case "constantRate":
            serviceClass = .signaling
        case "capacitySeeking":
            serviceClass = .responsiveData
        default:
            serviceClass = .bestEffort
        }
        
        // Note: Service class cannot be changed after connection creation
        // Store for future connections
        connectionProperties["serviceClass"] = serviceClass
    }
    
    // MARK: - Private Methods
    
    private func createNWParameters() -> NWParameters {
        let properties = preconnection.transportProperties
        let params: NWParameters
        
        // Select protocol based on transport properties
        if properties.reliability == .require {
            params = NWParameters.tcp
        } else {
            params = NWParameters.udp
        }
        
        // Configure TLS if needed
        if preconnection.securityParameters.allowedSecurityProtocols != nil {
            params.defaultProtocolStack.applicationProtocols.insert(NWProtocolTLS.Options(), at: 0)
        }
        
        // Configure other properties
        if properties.multipath != .disabled {
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
                params.multipathServiceType = properties.multipathPolicy == .handover ? .handover : .interactive
            }
        }
        
        return params
    }
    
    private func createNWEndpoint(from endpoint: RemoteEndpoint) throws -> NWEndpoint {
        if let ipAddress = endpoint.ipAddress, let port = endpoint.port {
            let host = NWEndpoint.Host(ipAddress)
            let port = NWEndpoint.Port(integerLiteral: port)
            return NWEndpoint.hostPort(host: host, port: port)
        } else if let hostName = endpoint.hostName, let port = endpoint.port {
            let host = NWEndpoint.Host(hostName)
            let port = NWEndpoint.Port(integerLiteral: port)
            return NWEndpoint.hostPort(host: host, port: port)
        } else {
            throw TransportError.invalidEndpoint
        }
    }
    
    private func convertNWEndpointToSocketAddress(_ endpoint: NWEndpoint) -> SocketAddress? {
        switch endpoint {
        case let .hostPort(host, port):
            let portNumber = port.rawValue
            switch host {
            case let .ipv4(address):
                return .ipv4(address: "\(address)", port: portNumber)
            case let .ipv6(address):
                return .ipv6(address: "\(address)", port: portNumber, scopeId: 0)
            case .name(_, _):
                // For hostnames, we can't convert directly to SocketAddress
                // This would need resolution
                return nil
            @unknown default:
                return nil
            }
        default:
            return nil
        }
    }
    
    private func convertNWEndpointToRemoteEndpoint(_ endpoint: NWEndpoint) -> RemoteEndpoint? {
        switch endpoint {
        case let .hostPort(host, port):
            var remoteEndpoint = RemoteEndpoint()
            remoteEndpoint.port = port.rawValue
            
            switch host {
            case let .ipv4(address):
                remoteEndpoint.ipAddress = "\(address)"
            case let .ipv6(address):
                remoteEndpoint.ipAddress = "\(address)"
            case let .name(hostname, _):
                remoteEndpoint.hostName = hostname
            @unknown default:
                return nil
            }
            
            return remoteEndpoint
            
        default:
            return nil
        }
    }
    
    private func convertNWEndpointToLocalEndpoint(_ endpoint: NWEndpoint?) -> LocalEndpoint? {
        guard let endpoint = endpoint else { return nil }
        
        switch endpoint {
        case let .hostPort(host, port):
            var localEndpoint = LocalEndpoint()
            localEndpoint.port = port.rawValue
            
            switch host {
            case let .ipv4(address):
                localEndpoint.ipAddress = "\(address)"
            case let .ipv6(address):
                localEndpoint.ipAddress = "\(address)"
            case .name(_, _):
                // Local endpoints typically don't use hostnames
                break
            @unknown default:
                return nil
            }
            
            return localEndpoint
            
        default:
            return nil
        }
    }
}

// Connection Group support
final class AppleConnectionGroup: @unchecked Sendable {
    private var connections: [AppleConnection] = []
    private let queue = DispatchQueue(label: "connection.group", attributes: .concurrent)
    
    func addConnection(_ connection: AppleConnection) {
        queue.async(flags: .barrier) { [weak self] in
            self?.connections.append(connection)
        }
    }
    
    func removeConnection(_ connection: AppleConnection) {
        queue.async(flags: .barrier) { [weak self] in
            self?.connections.removeAll { $0 === connection }
        }
    }
    
    func propagateProperty(_ property: ConnectionProperty, value: Any, excludingConnection: AppleConnection) async {
        // Note: This would require careful handling of Sendable constraints
        // For now, leave unimplemented
    }
}

/// Transport errors
enum TransportError: Error, LocalizedError {
    case noRemoteEndpoint
    case notConnected
    case connectionClosed
    case establishmentFailed
    case establishmentTimeout
    case invalidEndpoint
    case invalidInterface
    case cannotSend
    case cannotReceive
    case messageExpired
    case connectionNotViable
    case resolutionFailed
    
    var errorDescription: String? {
        switch self {
        case .noRemoteEndpoint:
            return "No remote endpoint specified"
        case .notConnected:
            return "Connection is not established"
        case .connectionClosed:
            return "Connection has been closed"
        case .establishmentFailed:
            return "Failed to establish connection"
        case .establishmentTimeout:
            return "Connection establishment timed out"
        case .invalidEndpoint:
            return "Invalid endpoint configuration"
        case .invalidInterface:
            return "Invalid network interface"
        case .cannotSend:
            return "Connection cannot send data"
        case .cannotReceive:
            return "Connection cannot receive data"
        case .messageExpired:
            return "Message expired before sending"
        case .connectionNotViable:
            return "Connection is no longer viable"
        case .resolutionFailed:
            return "Failed to resolve hostname"
        }
    }
}

// Extension to support connection property helpers
extension ConnectionProperty {
    var key: String {
        switch self {
        case .keepAlive:
            return "keepAliveTimeout"
        case .noDelay:
            return "noDelay"
        case .connectionTimeout:
            return "connTimeout"
        case .retransmissionTimeout:
            return "retransmissionTimeout"
        case .multipathPolicy:
            return "multipathPolicy"
        case .priority:
            return "connPriority"
        case .trafficClass:
            return "trafficClass"
        case .receiveBufferSize:
            return "receiveBufferSize"
        case .sendBufferSize:
            return "sendBufferSize"
        }
    }
    
    var isEntangled: Bool {
        // All properties except priority are entangled in a connection group
        switch self {
        case .priority:
            return false
        default:
            return true
        }
    }
}

#endif
