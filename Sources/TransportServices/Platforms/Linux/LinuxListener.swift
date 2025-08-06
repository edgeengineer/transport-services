//
//  LinuxListener.swift
//  
//
//  Maximilian Alexander
//

#if os(Linux)
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#else
#error("Unsupported C library")
#endif

#if !hasFeature(Embedded)
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
#endif

import Synchronization

/// Linux platform-specific listener implementation using BSD sockets
public final class LinuxListener: Listener, @unchecked Sendable {
    public let preconnection: Preconnection
    public let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    private let stateLock = Mutex<Void>(())
    private var listenSocketFd: Int32 = -1
    private var _state: ListenerState = .setup
    public private(set) var state: ListenerState {
        get {
            return stateLock.withLock { _ in _state }
        }
        set {
            stateLock.withLock { _ in _state = newValue }
        }
    }
    private var _group: ConnectionGroup?
    public private(set) var group: ConnectionGroup? {
        get {
            return stateLock.withLock { _ in _group }
        }
        set {
            stateLock.withLock { _ in _group = newValue }
        }
    }
    
    public init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
    }
    
    // MARK: - Listener Protocol Implementation
    
    public func setNewConnectionLimit(_ value: UInt?) async {
        // TODO: Implement connection limit
    }
    
    public func getNewConnectionLimit() async -> UInt? {
        // TODO: Implement connection limit
        return nil
    }
    
    public func getAcceptedConnectionCount() async -> UInt {
        // TODO: Implement connection counting
        return 0
    }
    
    public func getProperties() async -> TransportProperties {
        return preconnection.transportProperties
    }
    
    public func listen() async throws {
        guard let localEndpoint = preconnection.localEndpoints.first else {
            throw LinuxTransportError.noAddressSpecified
        }
        
        do {
            // Create socket based on transport properties
            let properties = preconnection.transportProperties
            let socketType = properties.reliability == .require ? LinuxCompat.SOCK_STREAM : LinuxCompat.SOCK_DGRAM
            let `protocol` = properties.reliability == .require ? IPPROTO_TCP : IPPROTO_UDP
            
            listenSocketFd = socket(AF_INET, socketType, Int32(`protocol`))
            guard listenSocketFd >= 0 else {
                throw LinuxTransportError.socketCreationFailed(errno: errno)
            }
            
            // Set socket to non-blocking mode
            setNonBlocking(listenSocketFd)
            
            // Configure socket options
            configureSocketOptions()
            
            // Bind to local endpoint
            try bindToLocalEndpoint(localEndpoint)
            
            // Start listening (TCP only)
            if properties.reliability == .require {
                let backlog: Int32 = 128
                let result = Glibc.listen(listenSocketFd, backlog)
                if result < 0 {
                    throw LinuxTransportError.listenFailed(errno: errno)
                }
            }
            
            // Register with event loop for accept events
            registerWithEventLoop()
            
            state = .ready
            eventHandler(.stopped(self))
            
            // Start accepting connections
            startAccepting()
            
        } catch {
            state = .failed
            if listenSocketFd >= 0 {
                close(listenSocketFd)
                listenSocketFd = -1
            }
            eventHandler(.establishmentError(reason: error.localizedDescription))
            throw error
        }
    }
    
    public func stop() async {
        guard state != .closed else { return }
        
        state = .closed
        
        if listenSocketFd >= 0 {
            // Unregister from event loop
            EventLoop.unregisterSocket(listenSocketFd)
            
            // Close the listening socket
            close(listenSocketFd)
            listenSocketFd = -1
        }
        
        eventHandler(.stopped(self))
    }
    
    public func newConnectionGroup() async -> ConnectionGroup {
        let group = ConnectionGroup()
        self.group = group
        return group
    }
    
    // MARK: - Private Helper Methods
    
    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
    
    private func configureSocketOptions() {
        guard listenSocketFd >= 0 else { return }
        
        // Enable SO_REUSEADDR to allow quick restart
        var reuseAddr: Int32 = 1
        setsockopt(listenSocketFd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        // Enable SO_REUSEPORT if available (for load balancing)
        #if os(Linux)
        var reusePort: Int32 = 1
        setsockopt(listenSocketFd, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }
    
    private func bindToLocalEndpoint(_ endpoint: LocalEndpoint) throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        
        guard let port = endpoint.port else {
            throw LinuxTransportError.missingPort
        }
        addr.sin_port = htons(port)
        
        if let ipAddress = endpoint.ipAddress {
            // Parse IP address string
            if inet_pton(AF_INET, ipAddress, &addr.sin_addr) != 1 {
                throw LinuxTransportError.invalidAddress
            }
        } else {
            // Bind to all interfaces
            addr.sin_addr.s_addr = INADDR_ANY
        }
        
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(listenSocketFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result < 0 {
            throw LinuxTransportError.bindFailed(errno: errno)
        }
    }
    
    private func registerWithEventLoop() {
        guard listenSocketFd >= 0 else { return }
        
        let events = UInt32(LinuxCompat.EPOLLIN | LinuxCompat.EPOLLET)
        _ = EventLoop.registerSocket(listenSocketFd, events: events) { [weak self] in
            guard let strongSelf = self else { return }
            Task { @Sendable in
                await strongSelf.handleAcceptEvent()
            }
        }
    }
    
    private func startAccepting() {
        Task {
            while state == .ready {
                await acceptConnections()
                // Small delay to prevent busy loop
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
    
    private func acceptConnections() async {
        guard listenSocketFd >= 0, state == .ready else { return }
        
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
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(listenSocketFd, sockaddrPtr, &addrLen)
            }
        }
        
        if clientFd < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // No pending connections
                return
            }
            // Accept error - errno contains the error code
            // Continue accepting connections
            return
        }
        
        // Set non-blocking mode for client socket
        let flags = fcntl(clientFd, F_GETFL, 0)
        _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK)
        
        // Create remote endpoint from client address
        let remoteEndpoint = createRemoteEndpoint(from: clientAddr)
        
        // Create new preconnection for the accepted connection
        let newPreconnection = createAcceptedPreconnection(remoteEndpoint: remoteEndpoint)
        
        // Create LinuxConnection for the accepted socket
        let connection = LinuxAcceptedConnection(
            socketFd: clientFd,
            preconnection: newPreconnection,
            eventHandler: eventHandler
        )
        
        // Add to connection group if configured
        if let group = self.group {
            await group.addConnection(connection)
            await connection.setGroup(group)
        }
        
        // Initialize the connection
        await connection.markReady()
        
        // Notify about new connection
        eventHandler(.connectionReceived(self, connection))
    }
    
    private func handleUDPConnection() async {
        // For UDP, we don't actually accept connections
        // Instead, we could handle incoming datagrams and create virtual connections
        // This is a simplified implementation
        
        var buffer = Array<UInt8>(repeating: 0, count: 65536)
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let bytesReceived = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                buffer.withUnsafeMutableBytes { bufferPtr in
                    recvfrom(listenSocketFd, bufferPtr.baseAddress, bufferPtr.count,
                            0, sockaddrPtr, &addrLen)
                }
            }
        }
        
        if bytesReceived > 0 {
            // Create a virtual connection for this UDP peer
            let remoteEndpoint = createRemoteEndpoint(from: clientAddr)
            let newPreconnection = createAcceptedPreconnection(remoteEndpoint: remoteEndpoint)
            
            let connection = LinuxUDPConnection(
                listenSocketFd: listenSocketFd,
                remoteAddr: clientAddr,
                preconnection: newPreconnection,
                eventHandler: eventHandler
            )
            
            // Add to connection group if configured
            if let group = self.group {
                await group.addConnection(connection)
                await connection.setGroup(group)
            }
            
            await connection.markReady()
            
            // Store the initial data
            let data = Data(buffer.prefix(bytesReceived))
            await connection.storeInitialData(data)
            
            eventHandler(.connectionReceived(self, connection))
        }
    }
    
    private func createRemoteEndpoint(from addr: sockaddr_in) -> RemoteEndpoint {
        var endpoint = RemoteEndpoint()
        
        // Convert IP address to string
        var ipBuffer = Array<CChar>(repeating: 0, count: Int(INET_ADDRSTRLEN))
        var mutableAddr = addr
        inet_ntop(AF_INET, &mutableAddr.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
        // Convert CChar array to UInt8 array for UTF8 decoding
        let validLength = ipBuffer.firstIndex(of: 0) ?? ipBuffer.count
        let uint8Buffer = ipBuffer[..<validLength].map { UInt8(bitPattern: $0) }
        endpoint.ipAddress = String(decoding: uint8Buffer, as: UTF8.self)
        
        // Convert port
        endpoint.port = ntohs(addr.sin_port)
        
        return endpoint
    }
    
    private func createAcceptedPreconnection(remoteEndpoint: RemoteEndpoint) -> Preconnection {
        // Create a new preconnection based on the listener's preconnection
        // but with the specific remote endpoint
        // Create a new preconnection based on the listener's preconnection
        // but with the specific remote endpoint
        if let linuxPreconnection = preconnection as? LinuxPreconnection {
            var newPreconnection = LinuxPreconnection()
            newPreconnection.localEndpoints = linuxPreconnection.localEndpoints
            newPreconnection.remoteEndpoints = [remoteEndpoint]
            newPreconnection.transportProperties = linuxPreconnection.transportProperties
            newPreconnection.securityParameters = linuxPreconnection.securityParameters
            return newPreconnection
        } else {
            fatalError("Expected LinuxPreconnection")
        }
    }
    
    private func handleAcceptEvent() async {
        // Called by event loop when socket is ready for accept
        Task {
            await acceptConnections()
        }
    }
}

/// Special connection class for accepted TCP connections
private final class LinuxAcceptedConnection: LinuxConnection, @unchecked Sendable {
    private let acceptedSocketFd: Int32
    
    init(socketFd: Int32, preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.acceptedSocketFd = socketFd
        super.init(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    func markReady() async {
        self.socketFd = acceptedSocketFd
        self._state = .established
        
        // Register with event loop
        registerWithEventLoop()
        
        // Notify ready
        eventHandler(.ready(self))
    }
    
    private func registerWithEventLoop() {
        guard socketFd >= 0 else { return }
        
        let events = UInt32(LinuxCompat.EPOLLIN | LinuxCompat.EPOLLOUT | LinuxCompat.EPOLLET)
        _ = EventLoop.registerSocket(socketFd, events: events) { [weak self] in
            guard let strongSelf = self else { return }
            Task { @Sendable in
                // Handle socket events
                _ = strongSelf
            }
        }
    }
}

/// Special connection class for UDP virtual connections
private final class LinuxUDPConnection: LinuxConnection, @unchecked Sendable {
    private let sharedSocketFd: Int32
    private let remoteAddress: sockaddr_in
    private var initialData: Data?
    
    init(listenSocketFd: Int32, remoteAddr: sockaddr_in, preconnection: Preconnection, 
         eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.sharedSocketFd = listenSocketFd
        self.remoteAddress = remoteAddr
        super.init(preconnection: preconnection, eventHandler: eventHandler)
    }
    
    func markReady() async {
        self.socketFd = sharedSocketFd
        self._state = .established
        eventHandler(.ready(self))
    }
    
    func storeInitialData(_ data: Data) async {
        self.initialData = data
    }
    
    override public func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        guard await state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        var addr = remoteAddress
        let result = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sharedSocketFd, buffer.baseAddress, buffer.count,
                          Int32(MSG_NOSIGNAL), sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        if result < 0 {
            throw LinuxTransportError.sendFailed(errno: errno)
        }
        
        eventHandler(.sent(self, context))
    }
    
    override public func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext) {
        // If we have initial data, return it first
        if let data = initialData {
            initialData = nil
            let context = MessageContext()
            eventHandler(.received(self, data, context))
            return (data, context)
        }
        
        // Otherwise, receive from socket filtering by remote address
        return try await super.receive(minIncompleteLength: minIncompleteLength, maxLength: maxLength)
    }
}

/// Listener state enumeration (Linux-specific)
public enum ListenerState: Sendable {
    case setup
    case ready
    case failed
    case closed
}

// Extend the error enum
extension LinuxTransportError {
    static func listenFailed(errno: Int32) -> LinuxTransportError {
        .connectFailed(errno: errno) // Reuse for simplicity
    }
}

#endif