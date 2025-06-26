#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore
import NIOPosix
@preconcurrency import NIOSSL

/// IP protocol stack implementation using SwiftNIO
final class IPStack: ProtocolStack, Sendable {
    typealias EndpointType = Endpoint
    
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    
    init(eventLoopGroup: MultiThreadedEventLoopGroup) {
        self.eventLoopGroup = eventLoopGroup
    }
    
    // MARK: - ProtocolStack Implementation
    
    func connect(
        to remote: Endpoint,
        from local: Endpoint?,
        with properties: TransportProperties,
        on eventLoop: EventLoop
    ) async throws -> Channel {
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: properties.disableNagle ? 1 : 0)
        
        // Bind to local endpoint if specified
        if local != nil {
            // Note: ClientBootstrap doesn't support explicit binding to local address
            // This would require using a lower-level API
            // For now, we'll skip local binding for client connections
        }
        
        // Connect to remote endpoint
        switch remote.kind {
        case .host(let hostname):
            return try await bootstrap.connect(host: hostname, port: Int(remote.port ?? 0)).get()
        case .ip(let address):
            return try await bootstrap.connect(host: address, port: Int(remote.port ?? 0)).get()
        case .bluetoothPeripheral, .bluetoothService:
            throw TransportError.establishmentFailure("IPStack cannot connect to BLE endpoints")
        }
    }
    
    func listen(
        on local: Endpoint,
        with properties: TransportProperties,
        on eventLoop: EventLoop
    ) async throws -> Channel {
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
        switch local.kind {
        case .host(let hostname):
            return try await bootstrap.bind(host: hostname, port: Int(local.port ?? 0)).get()
        case .ip(let address):
            return try await bootstrap.bind(host: address, port: Int(local.port ?? 0)).get()
        case .bluetoothPeripheral, .bluetoothService:
            throw TransportError.establishmentFailure("IPStack cannot listen on BLE endpoints")
        }
    }
    
    static func canHandle(endpoint: Endpoint) -> Bool {
        switch endpoint.kind {
        case .host, .ip:
            return true
        case .bluetoothPeripheral, .bluetoothService:
            return false
        }
    }
    
    static func priority(for properties: TransportProperties) -> Int {
        // Lower priority if low power is required
        switch properties.preferLowPower {
        case .require:
            return 0
        case .prefer:
            return 25
        case .noPreference:
            return 50
        case .avoid:
            return 75
        case .prohibit:
            return 100
        }
    }
}