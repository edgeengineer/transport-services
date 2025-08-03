//
//  LinuxConnection.swift
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

/// Linux platform-specific connection implementation using BSD sockets
public final actor LinuxConnection: Connection {
    public let preconnection: Preconnection
    public nonisolated let eventHandler: @Sendable (TransportServicesEvent) -> Void
    
    private var socketFd: Int32 = -1
    public private(set) var state: ConnectionState = .establishing
    public private(set) var group: ConnectionGroup?
    public private(set) var properties: TransportProperties
    
    // Buffer for partial messages
    private var receiveBuffer = Data()
    private let maxBufferSize = 65536
    
    public init(preconnection: Preconnection, eventHandler: @escaping @Sendable (TransportServicesEvent) -> Void) {
        self.preconnection = preconnection
        self.eventHandler = eventHandler
        self.properties = preconnection.transportProperties
    }
    
    // MARK: - Connection Protocol Implementation
    
    public func setGroup(_ group: ConnectionGroup?) {
        self.group = group
    }
    
    // MARK: - Connection Lifecycle
    
    /// Initiate the connection
    public func initiate() async {
        guard let remoteEndpoint = preconnection.remoteEndpoints.first else {
            eventHandler(.establishmentError(self, reason: "No remote endpoint specified"))
            return
        }
        
        do {
            // Create socket based on transport properties
            let socketType = properties.reliability == .require ? SOCK_STREAM : SOCK_DGRAM
            let `protocol` = properties.reliability == .require ? IPPROTO_TCP : IPPROTO_UDP
            
            socketFd = socket(AF_INET, socketType, Int32(`protocol`))
            guard socketFd >= 0 else {
                throw LinuxTransportError.socketCreationFailed(errno: errno)
            }
            
            // Set socket to non-blocking mode
            setNonBlocking(socketFd)
            
            // Configure socket options
            configureSocketOptions()
            
            // Bind to local endpoint if specified
            if let localEndpoint = preconnection.localEndpoints.first {
                try bindToLocalEndpoint(localEndpoint)
            }
            
            // Connect to remote endpoint
            try await connectToRemoteEndpoint(remoteEndpoint)
            
            // Register with event loop for I/O events
            registerWithEventLoop()
            
            state = .established
            eventHandler(.ready(self))
            
        } catch {
            state = .closed
            if socketFd >= 0 {
                close(socketFd)
                socketFd = -1
            }
            eventHandler(.establishmentError(self, reason: error.localizedDescription))
        }
    }
    
    public func close() async {
        guard state != .closed else { return }
        
        state = .closing
        
        if socketFd >= 0 {
            // Unregister from event loop
            EventLoop.unregisterSocket(socketFd)
            
            // Graceful shutdown for TCP
            if properties.reliability == .require {
                shutdown(socketFd, SHUT_RDWR)
            }
            
            close(socketFd)
            socketFd = -1
        }
        
        state = .closed
        eventHandler(.closed(self))
    }
    
    nonisolated public func abort() {
        Task {
            await self.abortInternal()
        }
    }
    
    private func abortInternal() {
        guard state != .closed else { return }
        
        state = .closed
        
        if socketFd >= 0 {
            EventLoop.unregisterSocket(socketFd)
            close(socketFd)
            socketFd = -1
        }
        
        eventHandler(.connectionError(self, reason: "Connection aborted"))
    }
    
    public func clone() async throws -> any Connection {
        let newConnection = LinuxConnection(
            preconnection: preconnection,
            eventHandler: eventHandler
        )
        
        if let group = self.group {
            await group.addConnection(newConnection)
            await newConnection.setGroup(group)
        }
        
        await newConnection.initiate()
        
        return newConnection
    }
    
    // MARK: - Data Transfer
    
    public func send(data: Data, context: MessageContext, endOfMessage: Bool) async throws {
        guard state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        guard socketFd >= 0 else {
            throw TransportServicesError.connectionClosed
        }
        
        let result = data.withUnsafeBytes { buffer in
            Glibc.send(socketFd, buffer.baseAddress, buffer.count, Int32(MSG_NOSIGNAL))
        }
        
        if result < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // Would block, need to wait for socket to be writable
                try await waitForWritable()
                // Retry send
                return try await send(data: data, context: context, endOfMessage: endOfMessage)
            } else {
                throw LinuxTransportError.sendFailed(errno: errno)
            }
        }
        
        eventHandler(.sent(self, context))
    }
    
    public func receive(minIncompleteLength: Int?, maxLength: Int?) async throws -> (Data, MessageContext) {
        guard state == .established else {
            throw TransportServicesError.connectionClosed
        }
        
        guard socketFd >= 0 else {
            throw TransportServicesError.connectionClosed
        }
        
        let bufferSize = min(maxLength ?? maxBufferSize, maxBufferSize)
        var buffer = Array<UInt8>(repeating: 0, count: bufferSize)
        
        let result = buffer.withUnsafeMutableBytes { buffer in
            recv(socketFd, buffer.baseAddress, buffer.count, 0)
        }
        
        if result < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // Would block, need to wait for data
                try await waitForReadable()
                // Retry receive
                return try await receive(minIncompleteLength: minIncompleteLength, maxLength: maxLength)
            } else {
                throw LinuxTransportError.receiveFailed(errno: errno)
            }
        } else if result == 0 {
            // Connection closed by peer
            await close()
            throw TransportServicesError.connectionClosed
        }
        
        let data = Data(buffer.prefix(result))
        let context = MessageContext()
        
        eventHandler(.received(self, data, context))
        
        return (data, context)
    }
    
    public func startReceiving(minIncompleteLength: Int?, maxLength: Int?) {
        Task {
            while state == .established {
                do {
                    let _ = try await receive(
                        minIncompleteLength: minIncompleteLength,
                        maxLength: maxLength
                    )
                } catch {
                    // Connection closed or error occurred
                    break
                }
            }
        }
    }
    
    // MARK: - Endpoint Management
    
    public func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // Not implemented for basic Linux sockets
        // Would require SCTP or custom multipath implementation
    }
    
    public func removeRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        // Not implemented for basic Linux sockets
    }
    
    public func addLocal(_ localEndpoints: [LocalEndpoint]) {
        // Not implemented for basic Linux sockets
    }
    
    public func removeLocal(_ localEndpoints: [LocalEndpoint]) {
        // Not implemented for basic Linux sockets
    }
    
    // MARK: - Private Helper Methods
    
    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
    
    private func configureSocketOptions() {
        guard socketFd >= 0 else { return }
        
        // Enable SO_REUSEADDR
        var reuseAddr: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        // Configure keep-alive if requested
        if properties.keepAlive != .prohibit {
            var keepAlive: Int32 = 1
            setsockopt(socketFd, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, socklen_t(MemoryLayout<Int32>.size))
        }
        
        // Configure TCP nodelay for low latency
        if properties.reliability == .require {
            var nodelay: Int32 = 1
            setsockopt(socketFd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
        }
    }
    
    private func bindToLocalEndpoint(_ endpoint: LocalEndpoint) throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        
        if let port = endpoint.port {
            addr.sin_port = htons(port)
        }
        
        if let ipAddress = endpoint.ipAddress {
            // Parse IP address string
            if inet_pton(AF_INET, ipAddress, &addr.sin_addr) != 1 {
                throw LinuxTransportError.invalidAddress
            }
        } else {
            addr.sin_addr.s_addr = INADDR_ANY
        }
        
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result < 0 {
            throw LinuxTransportError.bindFailed(errno: errno)
        }
    }
    
    private func connectToRemoteEndpoint(_ endpoint: RemoteEndpoint) async throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        
        guard let port = endpoint.port else {
            throw LinuxTransportError.missingPort
        }
        addr.sin_port = htons(port)
        
        // Resolve hostname if needed
        if let hostName = endpoint.hostName {
            let addresses = try await resolveHostname(hostName)
            guard let firstAddress = addresses.first else {
                throw LinuxTransportError.resolutionFailed
            }
            addr.sin_addr = firstAddress
        } else if let ipAddress = endpoint.ipAddress {
            if inet_pton(AF_INET, ipAddress, &addr.sin_addr) != 1 {
                throw LinuxTransportError.invalidAddress
            }
        } else {
            throw LinuxTransportError.noAddressSpecified
        }
        
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(socketFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result < 0 && errno != EINPROGRESS {
            throw LinuxTransportError.connectFailed(errno: errno)
        }
        
        // Wait for connection to complete (non-blocking)
        if errno == EINPROGRESS {
            try await waitForConnection()
        }
    }
    
    private func resolveHostname(_ hostname: String) async throws -> [in_addr] {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = properties.reliability == .require ? SOCK_STREAM : SOCK_DGRAM
                
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, nil, &hints, &result)
                
                guard status == 0 else {
                    continuation.resume(throwing: LinuxTransportError.resolutionFailed)
                    return
                }
                
                defer { freeaddrinfo(result) }
                
                var addresses: [in_addr] = []
                var current = result
                while let addr = current {
                    if addr.pointee.ai_family == AF_INET {
                        let sockaddrIn = addr.pointee.ai_addr!.withMemoryRebound(
                            to: sockaddr_in.self,
                            capacity: 1
                        ) { $0.pointee }
                        addresses.append(sockaddrIn.sin_addr)
                    }
                    current = addr.pointee.ai_next
                }
                
                continuation.resume(returning: addresses)
            }
        }
    }
    
    private func registerWithEventLoop() {
        guard socketFd >= 0 else { return }
        
        let events = UInt32(EPOLLIN | EPOLLOUT | EPOLLET)
        _ = EventLoop.registerSocket(socketFd, events: events) { [weak self] in
            Task {
                await self?.handleSocketEvent()
            }
        }
    }
    
    private func handleSocketEvent() {
        // Handle socket events (called by event loop)
        // This would process any pending I/O operations
    }
    
    private func waitForWritable() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Register for write events and wait
            // This is simplified - actual implementation would integrate with epoll
            continuation.resume()
        }
    }
    
    private func waitForReadable() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Register for read events and wait
            // This is simplified - actual implementation would integrate with epoll
            continuation.resume()
        }
    }
    
    private func waitForConnection() async throws {
        // Wait for connection to complete (for non-blocking connect)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                // Check socket error status
                var error: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                let result = getsockopt(socketFd, SOL_SOCKET, SO_ERROR, &error, &len)
                
                if result < 0 || error != 0 {
                    continuation.resume(throwing: LinuxTransportError.connectFailed(errno: error))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Linux-specific transport errors
enum LinuxTransportError: Error, LocalizedError {
    case socketCreationFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case connectFailed(errno: Int32)
    case sendFailed(errno: Int32)
    case receiveFailed(errno: Int32)
    case invalidAddress
    case missingPort
    case noAddressSpecified
    case resolutionFailed
    
    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let errno):
            return "Failed to create socket: \(String(cString: strerror(errno)))"
        case .bindFailed(let errno):
            return "Failed to bind socket: \(String(cString: strerror(errno)))"
        case .connectFailed(let errno):
            return "Failed to connect: \(String(cString: strerror(errno)))"
        case .sendFailed(let errno):
            return "Failed to send data: \(String(cString: strerror(errno)))"
        case .receiveFailed(let errno):
            return "Failed to receive data: \(String(cString: strerror(errno)))"
        case .invalidAddress:
            return "Invalid IP address format"
        case .missingPort:
            return "Port number is required"
        case .noAddressSpecified:
            return "No address specified for connection"
        case .resolutionFailed:
            return "Failed to resolve hostname"
        }
    }
}

#endif