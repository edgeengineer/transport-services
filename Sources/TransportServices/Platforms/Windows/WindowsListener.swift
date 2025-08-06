//
//  WindowsListener.swift
//  
//
//  Maximilian Alexander
//

#if os(Windows)
import WinSDK
import Foundation

/// Windows platform-specific listener implementation using Winsock2
public final actor WindowsListener: Listener {
    public let preconnection: Preconnection
    public nonisolated let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    private var listenSocket: SOCKET = INVALID_SOCKET
    public internal(set) var state: ListenerState = .setup
    public private(set) var group: ConnectionGroup?
    private var connectionLimit: UInt?
    private var acceptedCount: UInt = 0
    
    public init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        
        // Initialize Winsock if not already done
        WindowsCompat.initializeWinsock()
    }
    
    // MARK: - Listener Protocol Implementation
    
    public func listen() async throws {
        guard let localEndpoint = preconnection.localEndpoints.first else {
            throw WindowsTransportError.noAddressSpecified
        }
        
        do {
            // Create socket based on transport properties
            let properties = preconnection.transportProperties
            let family = WindowsCompat.AF_INET // TODO: Support IPv6
            let socketType = properties.reliability == .require ? WindowsCompat.SOCK_STREAM : WindowsCompat.SOCK_DGRAM
            let proto = properties.reliability == .require ? WindowsCompat.IPPROTO_TCP : WindowsCompat.IPPROTO_UDP
            
            guard let sock = WindowsCompat.socket(family: family, type: socketType, proto: proto) else {
                throw WindowsTransportError.socketCreationFailed(WindowsCompat.getLastSocketError())
            }
            
            self.listenSocket = sock
            
            // Set socket to non-blocking mode
            guard WindowsCompat.setNonBlocking(listenSocket) else {
                throw WindowsTransportError.socketCreationFailed(WindowsCompat.getLastSocketError())
            }
            
            // Configure socket options
            configureSocketOptions()
            
            // Bind to local endpoint
            try bindToLocalEndpoint(localEndpoint)
            
            // Start listening (TCP only)
            if properties.reliability == .require {
                let backlog: Int32 = 128
                let result = WinSDK.listen(listenSocket, backlog)
                if result == SOCKET_ERROR {
                    throw WindowsTransportError.listenFailed(WindowsCompat.getLastSocketError())
                }
            }
            
            // Associate socket with IOCP
            guard EventLoop.associateSocket(listenSocket, handler: { [weak self] _ in
                // Handle accept events
                Task { [weak self] in
                    await self?.acceptConnections()
                }
            }) else {
                throw WindowsTransportError.iocpError(Int32(GetLastError()))
            }
            
            state = .ready
            // Note: No specific event for listener becoming ready
            
            // Start accepting connections
            startAccepting()
            
        } catch {
            state = .failed
            if listenSocket != INVALID_SOCKET {
                closesocket(listenSocket)
                listenSocket = INVALID_SOCKET
            }
            eventHandler(.stopped(self))
            throw error
        }
    }
    
    public func stop() async {
        guard state != .closed else { return }
        
        state = .closed
        
        if listenSocket != INVALID_SOCKET {
            closesocket(listenSocket)
            listenSocket = INVALID_SOCKET
        }
        
        eventHandler(.stopped(self))
    }
    
    public func setNewConnectionLimit(_ value: UInt?) {
        self.connectionLimit = value
    }
    
    public func getNewConnectionLimit() -> UInt? {
        return connectionLimit
    }
    
    public func getAcceptedConnectionCount() -> UInt {
        return acceptedCount
    }
    
    public func getProperties() -> TransportProperties {
        return preconnection.transportProperties
    }
    
    public func newConnectionGroup() async -> ConnectionGroup {
        let group = ConnectionGroup()
        self.group = group
        return group
    }
    
    // MARK: - Private Helper Methods
    
    private func configureSocketOptions() {
        guard listenSocket != INVALID_SOCKET else { return }
        
        // Enable SO_REUSEADDR to allow quick restart
        var reuseAddr = TRUE
        setsockopt(listenSocket, WindowsCompat.SOL_SOCKET, WindowsCompat.SO_REUSEADDR,
                  &reuseAddr, Int32(MemoryLayout<WindowsBool>.size))
        
        // Enable SO_EXCLUSIVEADDRUSE on Windows for security
        var exclusive = TRUE
        setsockopt(listenSocket, WindowsCompat.SOL_SOCKET, SO_EXCLUSIVEADDRUSE,
                  &exclusive, Int32(MemoryLayout<WindowsBool>.size))
    }
    
    private func bindToLocalEndpoint(_ endpoint: LocalEndpoint) throws {
        guard let port = endpoint.port else {
            throw WindowsTransportError.missingPort
        }
        
        let addr = WindowsCompat.createSockaddrIn(
            address: endpoint.ipAddress,
            port: port
        )
        
        var mutableAddr = addr
        let result = withUnsafePointer(to: &mutableAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(listenSocket, sockaddrPtr, Int32(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result == SOCKET_ERROR {
            throw WindowsTransportError.bindFailed(WindowsCompat.getLastSocketError())
        }
    }
    
    private func startAccepting() {
        Task {
            while state == .ready {
                // Check connection limit
                if let limit = connectionLimit, acceptedCount >= limit {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    continue
                }
                
                await acceptConnections()
                // Small delay to prevent busy loop
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
    
    private func acceptConnections() async {
        guard listenSocket != INVALID_SOCKET, state == .ready else { return }
        
        let properties = preconnection.transportProperties
        
        if properties.reliability == .require {
            // TCP accept
            await acceptTCPConnection()
        } else {
            // UDP "accept" (handle incoming datagrams)
            await handleUDPConnection()
        }
    }
    
    private func acceptTCPConnection() async {
        let clientAddr = sockaddr_in()
        var addrLen = Int32(MemoryLayout<sockaddr_in>.size)
        
        var mutableAddr = clientAddr
        let clientSocket = withUnsafeMutablePointer(to: &mutableAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(listenSocket, sockaddrPtr, &addrLen)
            }
        }
        
        if clientSocket == INVALID_SOCKET {
            let error = WindowsCompat.getLastSocketError()
            if error == WSAEWOULDBLOCK {
                // No pending connections
                return
            }
            // Accept error - continue accepting connections
            return
        }
        
        // Set non-blocking mode for client socket
        _ = WindowsCompat.setNonBlocking(clientSocket)
        
        // Create remote endpoint from client address
        let remoteEndpoint = createRemoteEndpoint(from: mutableAddr)
        
        // Create new preconnection for the accepted connection
        let newPreconnection = createAcceptedPreconnection(remoteEndpoint: remoteEndpoint)
        
        // Create WindowsConnection for the accepted socket
        let connection = WindowsConnection(
            preconnection: newPreconnection,
            eventHandler: eventHandler
        )
        
        // Set the socket directly on the connection
        await connection.setAcceptedSocket(clientSocket)
        
        // Add to connection group if configured
        if let group = self.group {
            await group.addConnection(connection)
            await connection.setGroup(group)
        }
        
        // Mark as established and notify
        await connection.markEstablished()
        
        // Increment accepted count
        acceptedCount += 1
        
        // Notify about new connection
        eventHandler(.connectionReceived(self, connection))
    }
    
    private func handleUDPConnection() async {
        // For UDP, we don't actually accept connections
        // Instead, we could handle incoming datagrams and create virtual connections
        
        var buffer = Array<CChar>(repeating: 0, count: 65536)
        let clientAddr = sockaddr_in()
        var addrLen = Int32(MemoryLayout<sockaddr_in>.size)
        
        var mutableAddr = clientAddr
        let bytesReceived = withUnsafeMutablePointer(to: &mutableAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                recvfrom(listenSocket, &buffer, Int32(buffer.count), 0, sockaddrPtr, &addrLen)
            }
        }
        
        if bytesReceived > 0 {
            // Create a virtual connection for this UDP peer
            let remoteEndpoint = createRemoteEndpoint(from: mutableAddr)
            let newPreconnection = createAcceptedPreconnection(remoteEndpoint: remoteEndpoint)
            
            let connection = WindowsConnection(
                preconnection: newPreconnection,
                eventHandler: eventHandler
            )
            
            // Configure for UDP with shared socket
            await connection.setUDPSocket(listenSocket, remoteAddr: mutableAddr)
            
            // Add to connection group if configured
            if let group = self.group {
                await group.addConnection(connection)
                await connection.setGroup(group)
            }
            
            // Mark as established
            await connection.markEstablished()
            
            // Store initial data for the first receive
            let data = Data(bytes: buffer, count: Int(bytesReceived))
            await connection.setInitialData(data)
            
            acceptedCount += 1
            
            eventHandler(.connectionReceived(self, connection))
        }
    }
    
    private func createRemoteEndpoint(from addr: sockaddr_in) -> RemoteEndpoint {
        var endpoint = RemoteEndpoint()
        
        // Convert IP address to string
        var mutableAddr = addr
        withUnsafePointer(to: &mutableAddr.sin_addr) { ptr in
            if let ip = WindowsCompat.ipToString(family: WindowsCompat.AF_INET, addr: ptr) {
                endpoint.ipAddress = ip
            }
        }
        
        // Convert port
        endpoint.port = ntohs(addr.sin_port)
        
        return endpoint
    }
    
    private func createAcceptedPreconnection(remoteEndpoint: RemoteEndpoint) -> Preconnection {
        // Create a new preconnection based on the listener's preconnection
        // but with the specific remote endpoint
        if let windowsPreconnection = preconnection as? WindowsPreconnection {
            let newPreconnection = windowsPreconnection.clone()
            newPreconnection.remoteEndpoints = [remoteEndpoint]
            return newPreconnection
        } else {
            // Fallback - create new WindowsPreconnection
            return WindowsPreconnection(
                localEndpoints: preconnection.localEndpoints,
                remoteEndpoints: [remoteEndpoint],
                transportProperties: preconnection.transportProperties,
                securityParameters: preconnection.securityParameters
            )
        }
    }
}

// Removed WindowsAcceptedConnection and WindowsUDPConnection classes
// as actors cannot be inherited in Swift. Instead, we add methods 
// to WindowsConnection to handle accepted sockets and UDP sockets.

/// Listener state enumeration (Windows-specific)
public enum ListenerState: Sendable {
    case setup
    case ready
    case failed
    case closed
}

// Windows-specific constants
private let WSAEWOULDBLOCK = Int32(10035)
private let SO_EXCLUSIVEADDRUSE = Int32(-5)  // 0xfffffffb as signed Int32
private let TRUE = WindowsBool(true)

#endif