#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore
import Bluetooth
import GATT

#if os(Linux)
import BluetoothLinux
#endif

/// Bluetooth protocol stack implementation using PureSwift/Bluetooth
/// 
/// Note: This implementation uses the test L2CAP sockets as a demonstration.
/// For production use, you would need to use platform-specific implementations:
/// - Linux: BluetoothLinux.L2CAPSocket
/// - Darwin: CoreBluetooth-based implementation
final class BluetoothStack: ProtocolStack, Sendable {
    typealias EndpointType = Endpoint
    
    /// Initialize the Bluetooth stack
    init() {
        // Initialization will happen on first use
    }
    
    // MARK: - ProtocolStack Implementation
    
    func connect(
        to remote: Endpoint,
        from local: Endpoint?,
        with properties: TransportProperties,
        on eventLoop: EventLoop
    ) async throws -> Channel {
        // Ensure we have a Bluetooth endpoint
        guard case let .bluetoothPeripheral(peripheralUUID, _) = remote.kind else {
            throw TransportError.establishmentFailure("BluetoothStack requires Bluetooth endpoint")
        }
        
        // Get local address (use zero address if not specified)
        let localAddress: BluetoothAddress
        if let local = local,
           case let .bluetoothService(serviceUUID, _) = local.kind {
            // Convert service UUID to address (simplified for demo)
            // Use first 6 bytes of UUID for address
            var bytes: BluetoothAddress.ByteValue = (0, 0, 0, 0, 0, 0)
            let uuidBytes = withUnsafeBytes(of: serviceUUID.hashValue.littleEndian) { Array($0) }
            bytes.0 = uuidBytes[0]
            bytes.1 = uuidBytes[1]
            bytes.2 = uuidBytes[2]
            bytes.3 = uuidBytes[3]
            bytes.4 = uuidBytes[4]
            bytes.5 = uuidBytes[5]
            localAddress = BluetoothAddress(bytes: bytes)
        } else {
            localAddress = .zero
        }
        
        // Convert peripheral UUID to BluetoothAddress (simplified for demo)
        var remoteBytes: BluetoothAddress.ByteValue = (0, 0, 0, 0, 0, 0)
        let remoteUuidBytes = withUnsafeBytes(of: peripheralUUID.hashValue.littleEndian) { Array($0) }
        remoteBytes.0 = remoteUuidBytes[0]
        remoteBytes.1 = remoteUuidBytes[1]
        remoteBytes.2 = remoteUuidBytes[2]
        remoteBytes.3 = remoteUuidBytes[3]
        remoteBytes.4 = remoteUuidBytes[4]
        remoteBytes.5 = remoteUuidBytes[5]
        let remoteAddress = BluetoothAddress(bytes: remoteBytes)
        
        // Create mock Bluetooth channel for demonstration
        // Note: In production, use platform-specific L2CAP implementation
        // - Linux: BluetoothLinux.L2CAPSocket
        // - Darwin: CoreBluetooth CBL2CAPChannel
        
        // Create Bluetooth channel using our implementation
        let channel = BluetoothChannel(
            localAddress: localAddress,
            remoteAddress: remoteAddress,
            eventLoop: eventLoop
        )
        
        // Register and connect the channel
        do {
            try await channel.register().get()
            try await channel.connect(to: channel.remoteAddress!).get()
            return channel
        } catch {
            throw TransportError.establishmentFailure("Failed to establish Bluetooth connection: \(error)")
        }
    }
    
    func listen(
        on local: Endpoint,
        with properties: TransportProperties,
        on eventLoop: EventLoop
    ) async throws -> Channel {
        // Ensure we have a Bluetooth endpoint
        guard case let .bluetoothService(serviceUUID, psmOpt) = local.kind,
              let psm = psmOpt else {
            throw TransportError.establishmentFailure("BluetoothStack listen requires Bluetooth service endpoint with PSM")
        }
        
        // Convert service UUID to BluetoothAddress (simplified for demo)
        var localBytes: BluetoothAddress.ByteValue = (0, 0, 0, 0, 0, 0)
        let localUuidBytes = withUnsafeBytes(of: serviceUUID.hashValue.littleEndian) { Array($0) }
        localBytes.0 = localUuidBytes[0]
        localBytes.1 = localUuidBytes[1]
        localBytes.2 = localUuidBytes[2]
        localBytes.3 = localUuidBytes[3]
        localBytes.4 = localUuidBytes[4]
        localBytes.5 = localUuidBytes[5]
        let localAddress = BluetoothAddress(bytes: localBytes)
        
        // Create mock Bluetooth server channel for demonstration
        // Note: In production, use platform-specific L2CAP implementation
        // - Linux: BluetoothLinux.L2CAPSocket
        // - Darwin: CoreBluetooth CBPeripheralManager
        
        // Create Bluetooth server channel using our implementation  
        let channel = BluetoothServerChannel(
            localAddress: localAddress,
            psm: psm,
            eventLoop: eventLoop
        )
        
        // Register and bind the channel
        do {
            try await channel.register().get()
            try await channel.bind(to: channel.localAddress!).get()
            return channel
        } catch {
            throw TransportError.establishmentFailure("Failed to create Bluetooth listener: \(error)")
        }
    }
    
    static func canHandle(endpoint: Endpoint) -> Bool {
        switch endpoint.kind {
        case .bluetoothPeripheral, .bluetoothService:
            return true
        case .host, .ip:
            return false
        }
    }
    
    static func priority(for properties: TransportProperties) -> Int {
        // Higher priority if low power is preferred
        switch properties.preferLowPower {
        case .require:
            return 100
        case .prefer:
            return 75
        case .noPreference:
            return 50
        case .avoid:
            return 25
        case .prohibit:
            return 0
        }
    }
}