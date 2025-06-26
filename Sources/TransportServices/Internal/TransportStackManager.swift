#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore
import NIOPosix

/// Manages transport protocol stacks and selects the appropriate one
actor TransportStackManager {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let ipStack: IPStack
    private let bluetoothStack: BluetoothStack
    
    init(eventLoopGroup: MultiThreadedEventLoopGroup) {
        self.eventLoopGroup = eventLoopGroup
        self.ipStack = IPStack(eventLoopGroup: eventLoopGroup)
        self.bluetoothStack = BluetoothStack()
    }
    
    /// Select the best protocol stack for the given endpoint and properties
    func selectStack(for endpoint: Endpoint, properties: TransportProperties) -> (any ProtocolStack)? {
        // Check if endpoint type dictates the stack
        switch endpoint.kind {
        case .host, .ip:
            return ipStack
        case .bluetoothPeripheral, .bluetoothService:
            return bluetoothStack
        }
    }
    
    /// Connect to a remote endpoint, selecting the appropriate stack
    func connect(
        to remote: Endpoint,
        from local: Endpoint?,
        with properties: TransportProperties
    ) async throws -> Channel {
        guard let stack = selectStack(for: remote, properties: properties) else {
            throw TransportError.establishmentFailure("No suitable protocol stack for endpoint")
        }
        
        // Select event loop
        let eventLoop = eventLoopGroup.next()
        
        // Use the selected stack to connect
        if let ipStack = stack as? IPStack {
            return try await ipStack.connect(
                to: remote,
                from: local,
                with: properties,
                on: eventLoop
            )
        } else if let bluetoothStack = stack as? BluetoothStack {
            return try await bluetoothStack.connect(
                to: remote,
                from: local,
                with: properties,
                on: eventLoop
            )
        } else {
            throw TransportError.establishmentFailure("Unknown protocol stack type")
        }
    }
    
    /// Listen on a local endpoint, selecting the appropriate stack
    func listen(
        on local: Endpoint,
        with properties: TransportProperties
    ) async throws -> Channel {
        guard let stack = selectStack(for: local, properties: properties) else {
            throw TransportError.establishmentFailure("No suitable protocol stack for endpoint")
        }
        
        // Select event loop
        let eventLoop = eventLoopGroup.next()
        
        // Use the selected stack to listen
        if let ipStack = stack as? IPStack {
            return try await ipStack.listen(
                on: local,
                with: properties,
                on: eventLoop
            )
        } else if let bluetoothStack = stack as? BluetoothStack {
            return try await bluetoothStack.listen(
                on: local,
                with: properties,
                on: eventLoop
            )
        } else {
            throw TransportError.establishmentFailure("Unknown protocol stack type")
        }
    }
}