#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Bluetooth
import GATT

#if os(Linux)
import BluetoothLinux
#endif

/// Platform-agnostic L2CAP connection wrapper
protocol L2CAPConnection: Sendable {
    func send(_ data: Data) async throws
    func receive(_ maxSize: Int) async throws -> Data
    func close()
    var isConnected: Bool { get }
}

#if os(Linux)
/// Linux implementation using BluetoothLinux
final class LinuxL2CAPConnection: L2CAPConnection, @unchecked Sendable {
    private let socket: BluetoothLinux.L2CAPSocket
    private let queue = DispatchQueue(label: "l2cap.linux")
    
    init(socket: BluetoothLinux.L2CAPSocket) {
        self.socket = socket
    }
    
    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.socket.send(data)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func receive(_ maxSize: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let data = try self.socket.receive(maxSize)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func close() {
        queue.sync {
            socket.close()
        }
    }
    
    var isConnected: Bool {
        queue.sync {
            socket.status.state == .connected
        }
    }
}
#else
/// Mock implementation for non-Linux platforms
/// On Darwin, you would use CoreBluetooth's CBL2CAPChannel
final class MockL2CAPConnection: L2CAPConnection, @unchecked Sendable {
    private var _isConnected = true
    private let queue = DispatchQueue(label: "l2cap.mock")
    
    // In a real implementation, this would buffer data between send/receive
    private var dataBuffer: [Data] = []
    
    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self._isConnected else {
                    continuation.resume(throwing: TransportError.sendFailure("Not connected"))
                    return
                }
                // In mock, just store the data
                self.dataBuffer.append(data)
                continuation.resume()
            }
        }
    }
    
    func receive(_ maxSize: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self._isConnected else {
                    continuation.resume(throwing: TransportError.receiveFailure("Not connected"))
                    return
                }
                
                // In mock, return some test data or buffered data
                if !self.dataBuffer.isEmpty {
                    let data = self.dataBuffer.removeFirst()
                    continuation.resume(returning: Data(data.prefix(maxSize)))
                } else {
                    // Return empty data to simulate no data available
                    continuation.resume(returning: Data())
                }
            }
        }
    }
    
    func close() {
        queue.sync {
            _isConnected = false
            dataBuffer.removeAll()
        }
    }
    
    var isConnected: Bool {
        queue.sync {
            _isConnected
        }
    }
}
#endif

/// Factory for creating L2CAP connections
enum L2CAPConnectionFactory {
    static func createConnection(localAddress: BluetoothAddress, remoteAddress: BluetoothAddress) async throws -> L2CAPConnection {
        #if os(Linux)
        let socket = try BluetoothLinux.L2CAPSocket()
        try socket.bind(address: localAddress, psm: 0, addressType: .lowEnergy)
        try socket.connect(to: remoteAddress, type: .lowEnergy)
        return LinuxL2CAPConnection(socket: socket)
        #else
        // For non-Linux platforms, return mock
        // In a real implementation, this would use CoreBluetooth on Darwin
        return MockL2CAPConnection()
        #endif
    }
    
    static func createServer(localAddress: BluetoothAddress, psm: UInt16) async throws -> L2CAPServer {
        #if os(Linux)
        let socket = try BluetoothLinux.L2CAPSocket()
        try socket.bind(address: localAddress, psm: psm, addressType: .lowEnergy)
        try socket.listen(backlog: 10)
        return LinuxL2CAPServer(socket: socket)
        #else
        return MockL2CAPServer(localAddress: localAddress, psm: psm)
        #endif
    }
}

/// Platform-agnostic L2CAP server wrapper
protocol L2CAPServer: Sendable {
    func accept() async throws -> (connection: L2CAPConnection, remoteAddress: BluetoothAddress)
    func close()
}

#if os(Linux)
/// Linux L2CAP server implementation
final class LinuxL2CAPServer: L2CAPServer, @unchecked Sendable {
    private let socket: BluetoothLinux.L2CAPSocket
    private let queue = DispatchQueue(label: "l2cap.server.linux")
    
    init(socket: BluetoothLinux.L2CAPSocket) {
        self.socket = socket
    }
    
    func accept() async throws -> (connection: L2CAPConnection, remoteAddress: BluetoothAddress) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let (clientSocket, address) = try self.socket.accept()
                    let connection = LinuxL2CAPConnection(socket: clientSocket)
                    continuation.resume(returning: (connection, address))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func close() {
        queue.sync {
            socket.close()
        }
    }
}
#else
/// Mock L2CAP server for non-Linux platforms
final class MockL2CAPServer: L2CAPServer, @unchecked Sendable {
    private let localAddress: BluetoothAddress
    private let psm: UInt16
    private var isListening = true
    private let queue = DispatchQueue(label: "l2cap.server.mock")
    
    init(localAddress: BluetoothAddress, psm: UInt16) {
        self.localAddress = localAddress
        self.psm = psm
    }
    
    func accept() async throws -> (connection: L2CAPConnection, remoteAddress: BluetoothAddress) {
        // In mock mode, simulate waiting for a connection
        try await Task.sleep(for: .seconds(60))
        
        // This would normally block until a connection arrives
        // For mock, we'll throw an error to indicate no real implementation
        throw TransportError.establishmentFailure("Mock L2CAP server - no real connections available")
    }
    
    func close() {
        queue.sync {
            isListening = false
        }
    }
}
#endif