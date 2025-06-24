#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A passive object representing a potential Connection.
///
/// A Preconnection maintains the state that describes the properties of a
/// Connection that might exist in the future, as defined in RFC 9622 §6.
/// It serves as a template for creating Connections via initiating, listening,
/// or rendezvous operations.
///
/// ## Overview
///
/// The Preconnection object is configured during the preestablishment phase
/// with endpoints, transport properties, and security parameters. Once configured,
/// it can be used to:
/// - Initiate an outbound connection (client)
/// - Listen for inbound connections (server)
/// - Establish peer-to-peer connections (rendezvous)
///
/// ## Usage Examples
///
/// ### Client Connection
/// ```swift
/// let remote = RemoteEndpoint(kind: .host("example.com"))
/// remote.port = 443
/// 
/// let preconnection = Preconnection(
///     remote: [remote],
///     transport: TransportProperties(),
///     security: SecurityParameters()
/// )
/// 
/// let connection = try await preconnection.initiate()
/// ```
///
/// ### Server Listener
/// ```swift
/// let local = LocalEndpoint(kind: .host("0.0.0.0"))
/// local.port = 8080
/// 
/// let preconnection = Preconnection(
///     local: [local],
///     transport: TransportProperties()
/// )
/// 
/// let listener = try await preconnection.listen()
/// ```
///
/// ## Topics
///
/// ### Creating a Preconnection
/// - ``init(local:remote:transport:security:)``
///
/// ### Configuring Endpoints
/// - ``add(local:)``
/// - ``add(remote:)``
/// - ``resolve()``
///
/// ### Configuring Framers
/// - ``add(framer:)``
///
/// ### Establishing Connections
/// - ``initiate(timeout:)``
/// - ``initiateWithSend(_:timeout:)``
/// - ``listen()``
/// - ``rendezvous()``
///
/// ## RFC 9622 Compliance
///
/// This implementation follows RFC 9622 §6 (Preestablishment Phase) and §7
/// (Establishing Connections). Key requirements:
/// - At least one Local Endpoint MUST be specified for Listen
/// - At least one Remote Endpoint MUST be specified for Initiate
/// - Both Local and Remote Endpoints MUST be specified for Rendezvous
/// - Message Framers MUST be added during preestablishment
public final class Preconnection: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var localEndpoints: [LocalEndpoint]
    private var remoteEndpoints: [RemoteEndpoint]
    private let transportProperties: TransportProperties
    private let securityParameters: SecurityParameters
    private var framers: [any MessageFramer] = []
    
    // MARK: - Initialization
    
    /// Creates a new Preconnection with the specified endpoints and properties.
    ///
    /// A Preconnection represents a potential Connection configured with endpoints,
    /// transport properties, and security parameters. The requirements for endpoints
    /// depend on how the Preconnection will be used:
    ///
    /// - For ``initiate(timeout:)``: At least one Remote Endpoint MUST be specified.
    ///   Local Endpoints are optional; if not specified, the system will assign an
    ///   ephemeral local port.
    ///
    /// - For ``listen()``: At least one Local Endpoint MUST be specified.
    ///   Remote Endpoints are optional and can be used to constrain accepted connections.
    ///
    /// - For ``rendezvous()``: Both Local and Remote Endpoints MUST be specified.
    ///
    /// - Parameters:
    ///   - local: Array of Local Endpoints for this Preconnection.
    ///   - remote: Array of Remote Endpoints for this Preconnection.
    ///   - transport: Transport Properties for protocol selection.
    ///   - security: Security Parameters for connection security.
    ///
    /// ## Example
    /// ```swift
    /// // Client preconnection
    /// let preconnection = Preconnection(
    ///     remote: [RemoteEndpoint(kind: .host("api.example.com"))],
    ///     transport: TransportProperties()
    /// )
    /// ```
    public init(local: [LocalEndpoint] = [],
                remote: [RemoteEndpoint] = [],
                transport: TransportProperties = .init(),
                security: SecurityParameters = .init()) {
        self.localEndpoints = local
        self.remoteEndpoints = remote
        self.transportProperties = transport
        self.securityParameters = security
    }
    
    // MARK: - Endpoint Configuration
    
    /// Adds a Local Endpoint to this Preconnection.
    ///
    /// This method can only be called during the preestablishment phase,
    /// before any Connection establishment actions (initiate, listen, rendezvous).
    /// 
    /// Multiple Local Endpoints indicate that all are eligible for use.
    /// For example, they might correspond to:
    /// - Different interfaces on a multihomed host
    /// - Local interfaces and a STUN server for NAT traversal
    ///
    /// - Parameter local: The Local Endpoint to add.
    ///
    /// - Note: Changes to a Preconnection after establishment actions have
    ///   been called will not affect existing Connections or Listeners.
    public func add(local: LocalEndpoint) async {
        localEndpoints.append(local)
    }
    
    /// Adds a Remote Endpoint to this Preconnection.
    ///
    /// This method can only be called during the preestablishment phase,
    /// before any Connection establishment actions. It's particularly useful
    /// for rendezvous scenarios where Remote Endpoints are received via
    /// signaling channels.
    ///
    /// Multiple Remote Endpoints indicate equivalent services; the Transport
    /// Services System can choose any of them. Examples include:
    /// - Multiple network interfaces of a host
    /// - Server-reflexive addresses for NAT traversal
    /// - Load-balanced server instances
    ///
    /// - Parameter remote: The Remote Endpoint to add.
    ///
    /// ## Rendezvous Example
    /// ```swift
    /// // After receiving candidates from peer via signaling
    /// for candidate in remoteCandidates {
    ///     await preconnection.add(remote: candidate)
    /// }
    /// ```
    public func add(remote: RemoteEndpoint) async {
        remoteEndpoints.append(remote)
    }
    
    /// Adds a Message Framer to this Preconnection.
    ///
    /// Message Framers MUST be added during preestablishment, before any
    /// Connection establishment actions. Framers enable message boundary
    /// preservation on byte-stream transports.
    ///
    /// - Parameter framer: The Message Framer to add.
    ///
    /// - Important: According to RFC 9622 §6, Message Framers MUST be
    ///   added to the Preconnection during preestablishment.
    public func add(framer: any MessageFramer) async {
        framers.append(framer)
    }
    
    // MARK: - Resolution
    
    /// Resolves endpoint identifiers to concrete addresses.
    ///
    /// This action performs name resolution and discovers NAT bindings for
    /// the configured endpoints. It's particularly useful for rendezvous
    /// scenarios where resolved addresses need to be exchanged via signaling.
    ///
    /// For endpoints that support NAT binding discovery (e.g., STUN/TURN),
    /// this returns server-reflexive addresses in addition to local addresses.
    ///
    /// - Returns: A tuple containing resolved Local and Remote Endpoints.
    /// - Throws: ``TransportError`` if resolution fails.
    ///
    /// ## Rendezvous Example
    /// ```swift
    /// // Resolve local candidates for signaling
    /// let (localCandidates, _) = try await preconnection.resolve()
    /// // Send localCandidates to peer via signaling channel
    /// ```
    ///
    /// - Note: The set of Local Endpoints returned might not contain all
    ///   possible local interfaces, and available interfaces can change over time.
    public func resolve() async throws
        -> (resolvedLocal: [LocalEndpoint], resolvedRemote: [RemoteEndpoint]) {
        // Implementation would perform:
        // 1. DNS resolution for hostnames
        // 2. STUN/TURN binding discovery for NAT traversal
        // 3. Interface enumeration for local addresses
        return (localEndpoints, remoteEndpoints)
    }
    
    // MARK: - Connection Establishment
    
    /// Actively opens a Connection to a Remote Endpoint (client mode).
    ///
    /// Initiates establishment of a transport-layer connection to one of the
    /// configured Remote Endpoints. The Transport Services System will:
    /// 1. Select appropriate transport protocols based on properties
    /// 2. Resolve endpoint names to addresses
    /// 3. Attempt connection establishment
    /// 4. Return when at least one path is ready
    ///
    /// - Parameter timeout: Optional timeout for establishment.
    /// - Returns: An established ``Connection`` ready for data transfer.
    /// - Throws: ``TransportError/establishmentFailure(_:)`` if connection fails.
    ///
    /// ## Events
    /// The returned Connection may emit:
    /// - `Ready`: Connection established successfully
    /// - `EstablishmentError`: Connection failed
    ///
    /// ## Requirements
    /// - At least one Remote Endpoint MUST be specified
    /// - Local Endpoints are optional (ephemeral port if not specified)
    ///
    /// - Important: Changes to the Preconnection after calling initiate
    ///   will not affect the returned Connection.
    public func initiate(timeout: Duration? = nil) async throws -> Connection {
        // Validate preconditions
        guard !remoteEndpoints.isEmpty else {
            throw TransportError.establishmentFailure(
                "At least one Remote Endpoint must be specified for initiate"
            )
        }
        
        // Use the Transport Services implementation to create the connection
        return try await TransportServicesImpl.shared.initiate(
            remoteEndpoints: remoteEndpoints,
            localEndpoints: localEndpoints,
            properties: transportProperties,
            securityParameters: securityParameters,
            framers: framers
        )
    }
    
    /// Initiates a Connection and sends the first Message atomically.
    ///
    /// Combines connection establishment with transmission of the first Message.
    /// This enables optimizations like TCP Fast Open or QUIC 0-RTT when the
    /// Message is marked as safely replayable.
    ///
    /// - Parameters:
    ///   - firstMessage: The Message to send upon connection.
    ///   - timeout: Optional timeout for establishment.
    /// - Returns: An established ``Connection`` ready for data transfer.
    /// - Throws: ``TransportError`` if establishment or send fails.
    ///
    /// ## Performance Benefits
    /// This method can reduce latency by combining operations:
    /// - TCP Fast Open: SYN + data
    /// - QUIC 0-RTT: Immediate data transmission
    /// - TLS Early Data: When message is safely replayable
    ///
    /// - Important: Only use with safely replayable messages to avoid
    ///   security issues with 0-RTT protocols.
    public func initiateWithSend(_ firstMessage: Message,
                                 timeout: Duration? = nil) async throws -> Connection {
        // Validate preconditions
        guard !remoteEndpoints.isEmpty else {
            throw TransportError.establishmentFailure(
                "At least one Remote Endpoint must be specified for initiate"
            )
        }
        
        // Check if the message is safely replayable for 0-RTT
        guard firstMessage.context.safelyReplayable else {
            throw TransportError.establishmentFailure(
                "Message must be safely replayable for 0-RTT initiation"
            )
        }
        
        // Enable 0-RTT in transport properties
        var zeroRTTProperties = transportProperties
        zeroRTTProperties.zeroRTT = .require
        
        // Use the Transport Services implementation to create the connection
        let connection = try await TransportServicesImpl.shared.initiateWithSend(
            remoteEndpoints: remoteEndpoints,
            localEndpoints: localEndpoints,
            properties: zeroRTTProperties,
            securityParameters: securityParameters,
            framers: framers,
            firstMessage: firstMessage
        )
        
        return connection
    }
    
    /// Passively listens for incoming Connections (server mode).
    ///
    /// Creates a Listener that waits for incoming Connections from Remote
    /// Endpoints. The Listener will continue accepting Connections until
    /// explicitly stopped.
    ///
    /// - Returns: A ``Listener`` that emits incoming Connections.
    /// - Throws: ``TransportError/establishmentFailure(_:)`` if listen fails.
    ///
    /// ## Requirements
    /// - At least one Local Endpoint MUST be specified
    /// - Remote Endpoints are optional (for filtering connections)
    ///
    /// ## Listener Events
    /// The returned Listener emits:
    /// - `ConnectionReceived`: New inbound Connection
    /// - `EstablishmentError`: Listen operation failed
    /// - `Stopped`: Listener has stopped
    ///
    /// ## Example
    /// ```swift
    /// let listener = try await preconnection.listen()
    /// for try await connection in listener.newConnections {
    ///     Task { await handleConnection(connection) }
    /// }
    /// ```
    ///
    /// - Important: The Preconnection can be reused or disposed after
    ///   calling listen. Changes to it won't affect the Listener.
    public func listen() async throws -> Listener {
        // Validate preconditions
        guard !localEndpoints.isEmpty else {
            throw TransportError.establishmentFailure(
                "At least one Local Endpoint must be specified for listen"
            )
        }
        
        // Use the Transport Services implementation to create the listener
        return try await TransportServicesImpl.shared.listen(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            properties: transportProperties,
            securityParameters: securityParameters,
            framers: framers
        )
    }
    
    /// Establishes a peer-to-peer Connection using simultaneous open.
    ///
    /// Performs a rendezvous by simultaneously listening for incoming
    /// Connections and attempting outbound Connections. This is typically
    /// used with ICE-style connectivity checks for NAT traversal.
    ///
    /// The Transport Services Implementation will:
    /// 1. Probe reachability between all endpoint pairs
    /// 2. Perform STUN/TURN binding discovery if configured
    /// 3. Execute connectivity checks (similar to ICE)
    /// 4. Establish the best available path
    ///
    /// - Returns: An established ``Connection`` to the peer.
    /// - Throws: ``TransportError/establishmentFailure(_:)`` if rendezvous fails.
    ///
    /// ## Requirements
    /// - Both Local and Remote Endpoints MUST be specified
    /// - Endpoints should be exchanged via out-of-band signaling
    ///
    /// ## Typical Flow
    /// ```swift
    /// // 1. Configure local endpoints
    /// preconnection.add(local: stunEndpoint)
    /// 
    /// // 2. Resolve to get candidates
    /// let (locals, _) = try await preconnection.resolve()
    /// 
    /// // 3. Exchange candidates via signaling
    /// sendToSignaling(locals)
    /// let remotes = await receiveFromSignaling()
    /// 
    /// // 4. Add remote candidates
    /// for remote in remotes {
    ///     await preconnection.add(remote: remote)
    /// }
    /// 
    /// // 5. Perform rendezvous
    /// let connection = try await preconnection.rendezvous()
    /// ```
    ///
    /// ## Events
    /// - `RendezvousDone`: Connection established with peer
    /// - `EstablishmentError`: Rendezvous failed
    public func rendezvous() async throws -> Connection {
        // Validate preconditions
        guard !localEndpoints.isEmpty else {
            throw TransportError.establishmentFailure(
                "At least one Local Endpoint must be specified for rendezvous"
            )
        }
        guard !remoteEndpoints.isEmpty else {
            throw TransportError.establishmentFailure(
                "At least one Remote Endpoint must be specified for rendezvous"
            )
        }
        
        // Use the Transport Services implementation to perform rendezvous
        return try await TransportServicesImpl.shared.rendezvous(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            properties: transportProperties,
            securityParameters: securityParameters,
            framers: framers
        )
    }
    
    // MARK: - Multicast
    
    /// Creates a multicast sender connection.
    ///
    /// Establishes a Connection for sending data to a multicast group.
    /// The sender does not join the multicast group as a receiver.
    ///
    /// - Parameter endpoint: The multicast endpoint configuration.
    /// - Returns: A ``Connection`` configured for multicast sending.
    /// - Throws: ``TransportError`` if establishment fails.
    ///
    /// ## Example
    /// ```swift
    /// let multicast = MulticastEndpoint(
    ///     groupAddress: "239.1.1.1",
    ///     port: 5353,
    ///     ttl: 1
    /// )
    /// let sender = try await preconnection.multicastSend(to: multicast)
    /// ```
    public func multicastSend(to endpoint: MulticastEndpoint) async throws -> Connection {
        var props = transportProperties
        props.multicast.direction = .sendOnly
        
        return try await TransportServicesImpl.shared.createMulticastSender(
            multicastEndpoint: endpoint,
            properties: props
        )
    }
    
    /// Creates a multicast receiver listener.
    ///
    /// Establishes a Listener that joins a multicast group and creates
    /// individual Connections for each unique sender to the group.
    ///
    /// - Parameter endpoint: The multicast endpoint configuration.
    /// - Returns: A ``Listener`` that emits Connections for each sender.
    /// - Throws: ``TransportError`` if establishment fails.
    ///
    /// ## Example
    /// ```swift
    /// let multicast = MulticastEndpoint(
    ///     groupAddress: "239.1.1.1",
    ///     port: 5353
    /// )
    /// let receiver = try await preconnection.multicastReceive(from: multicast)
    /// for try await connection in receiver.newConnections {
    ///     // Handle data from this specific sender
    /// }
    /// ```
    public func multicastReceive(from endpoint: MulticastEndpoint) async throws -> MulticastListener {
        var props = transportProperties
        props.multicast.direction = .receiveOnly
        
        return try await TransportServicesImpl.shared.createMulticastReceiver(
            multicastEndpoint: endpoint,
            properties: props
        )
    }
}