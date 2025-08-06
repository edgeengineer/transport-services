//
//  LinuxPreconnection.swift
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

/// Linux platform-specific preconnection implementation
public struct LinuxPreconnection: Preconnection {
    public var localEndpoints: [LocalEndpoint]
    public var remoteEndpoints: [RemoteEndpoint]
    public var transportProperties: TransportProperties
    public var securityParameters: SecurityParameters
    
    public init(localEndpoints: [LocalEndpoint] = [],
                remoteEndpoints: [RemoteEndpoint] = [],
                transportProperties: TransportProperties = TransportProperties(),
                securityParameters: SecurityParameters = SecurityParameters()) {
        self.localEndpoints = localEndpoints
        self.remoteEndpoints = remoteEndpoints
        self.transportProperties = transportProperties
        self.securityParameters = securityParameters
    }
    
    // MARK: - Preconnection Protocol Implementation
    
    public func resolve() async -> (local: [LocalEndpoint], remote: [RemoteEndpoint]) {
        var resolvedLocal: [LocalEndpoint] = []
        var resolvedRemote: [RemoteEndpoint] = []
        
        // Resolve local endpoints
        for endpoint in localEndpoints {
            if endpoint.interface == "any" {
                // Get all available interfaces
                let interfaces = await getLocalInterfaces()
                for interface in interfaces {
                    var resolved = endpoint.clone()
                    resolved.interface = interface.name
                    resolved.ipAddress = interface.address
                    resolvedLocal.append(resolved)
                }
            } else {
                resolvedLocal.append(endpoint)
            }
        }
        
        // Resolve remote endpoints
        for endpoint in remoteEndpoints {
            if let hostName = endpoint.hostName {
                // Resolve hostname to IP addresses
                let addresses = await resolveHostname(hostName)
                for address in addresses {
                    var resolved = endpoint.clone()
                    resolved.ipAddress = address
                    resolved.hostName = nil // Clear hostname after resolution
                    resolvedRemote.append(resolved)
                }
            } else {
                resolvedRemote.append(endpoint)
            }
        }
        
        // If no local endpoints were specified, use default
        if resolvedLocal.isEmpty && !localEndpoints.isEmpty {
            resolvedLocal = localEndpoints
        }
        
        // If no remote endpoints were resolved, keep original
        if resolvedRemote.isEmpty && !remoteEndpoints.isEmpty {
            resolvedRemote = remoteEndpoints
        }
        
        return (resolvedLocal, resolvedRemote)
    }
    
    public func initiate(timeout: TimeInterval?, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Connection {
        let handler = eventHandler ?? { _ in }
        
        // Validate we have at least one remote endpoint
        guard !remoteEndpoints.isEmpty else {
            throw TransportServicesError.invalidConfiguration
        }
        
        // Create connection
        let connection = LinuxConnection(preconnection: self, eventHandler: handler)
        
        // Initiate connection with timeout if specified
        if let timeout = timeout {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await connection.initiate()
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw TransportServicesError.timeout
                }
                
                // Wait for first to complete (either connection or timeout)
                try await group.next()
                group.cancelAll()
            }
        } else {
            await connection.initiate()
        }
        
        return connection
    }
    
    public func initiateWithSend(messageData: Data, messageContext: MessageContext, timeout: TimeInterval?, eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Connection {
        // Initiate connection
        let connection = try await initiate(timeout: timeout, eventHandler: eventHandler)
        
        // Send initial data
        try await connection.send(data: messageData, context: messageContext, endOfMessage: true)
        
        return connection
    }
    
    public func listen(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> any Listener {
        let handler = eventHandler ?? { _ in }
        
        // Validate we have at least one local endpoint
        guard !localEndpoints.isEmpty else {
            throw TransportServicesError.invalidConfiguration
        }
        
        // Create listener
        let listener = LinuxListener(preconnection: self, eventHandler: handler)
        
        // Start listening
        try await listener.listen()
        
        return listener
    }
    
    public func rendezvous(eventHandler: ((@Sendable (TransportServicesEvent) -> Void))?) async throws -> (any Connection, any Listener) {
        let handler = eventHandler ?? { _ in }
        
        // Validate we have both local and remote endpoints
        guard !localEndpoints.isEmpty else {
            throw TransportServicesError.invalidConfiguration
        }
        guard !remoteEndpoints.isEmpty else {
            throw TransportServicesError.invalidConfiguration
        }
        
        // For rendezvous, we need to both listen and connect
        // This is a simplified implementation
        
        // Create listener
        let listener = LinuxListener(preconnection: self, eventHandler: handler)
        try await listener.listen()
        
        // Create connection
        let connection = LinuxConnection(preconnection: self, eventHandler: handler)
        await connection.initiate()
        
        return (connection, listener)
    }
    
    public mutating func addRemote(_ remoteEndpoints: [RemoteEndpoint]) {
        self.remoteEndpoints.append(contentsOf: remoteEndpoints)
    }
    
    // MARK: - Helper Methods
    
    /// Clone this preconnection
    func clone() -> LinuxPreconnection {
        return LinuxPreconnection(
            localEndpoints: localEndpoints,
            remoteEndpoints: remoteEndpoints,
            transportProperties: transportProperties,
            securityParameters: securityParameters
        )
    }
    
    private func getLocalInterfaces() async -> [(name: String, address: String)] {
        var interfaces: [(name: String, address: String)] = []
        
        // Get interface addresses using getifaddrs
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else {
            return interfaces
        }
        defer { freeifaddrs(ifaddrs) }
        
        var current = ifaddrs
        while let interface = current {
            let name = String(cString: interface.pointee.ifa_name)
            
            if let addr = interface.pointee.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_INET) {
                // IPv4 address
                let sockaddrIn = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var ipBuffer = Array<CChar>(repeating: 0, count: Int(INET_ADDRSTRLEN))
                var mutableAddr = sockaddrIn.sin_addr
                if inet_ntop(AF_INET, &mutableAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let validLength = ipBuffer.firstIndex(of: 0) ?? ipBuffer.count
                    let uint8Buffer = ipBuffer[..<validLength].map { UInt8(bitPattern: $0) }
                    let address = String(decoding: uint8Buffer, as: UTF8.self)
                    interfaces.append((name: name, address: address))
                }
            }
            
            current = interface.pointee.ifa_next
        }
        
        return interfaces
    }
    
    private func resolveHostname(_ hostname: String) async -> [String] {
        return await withCheckedContinuation { continuation in
            Task {
                var hints = addrinfo()
                hints.ai_family = AF_INET // IPv4 for simplicity
                hints.ai_socktype = Int32(transportProperties.reliability == .require ? LinuxCompat.SOCK_STREAM : LinuxCompat.SOCK_DGRAM)
                
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, nil, &hints, &result)
                
                guard status == 0 else {
                    continuation.resume(returning: [])
                    return
                }
                
                defer { freeaddrinfo(result) }
                
                var addresses: [String] = []
                var current = result
                while let addr = current {
                    if addr.pointee.ai_family == AF_INET {
                        let sockaddrIn = addr.pointee.ai_addr!.withMemoryRebound(
                            to: sockaddr_in.self,
                            capacity: 1
                        ) { $0.pointee }
                        
                        var ipBuffer = Array<CChar>(repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var mutableAddr = sockaddrIn.sin_addr
                        if inet_ntop(AF_INET, &mutableAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                            let validLength = ipBuffer.firstIndex(of: 0) ?? ipBuffer.count
                            let uint8Buffer = ipBuffer[..<validLength].map { UInt8(bitPattern: $0) }
                            addresses.append(String(decoding: uint8Buffer, as: UTF8.self))
                        }
                    }
                    current = addr.pointee.ai_next
                }
                
                continuation.resume(returning: addresses)
            }
        }
    }
}

// Helper extensions for cloning endpoints
extension LocalEndpoint {
    func clone() -> LocalEndpoint {
        var endpoint = LocalEndpoint()
        endpoint.interface = self.interface
        endpoint.port = self.port
        endpoint.ipAddress = self.ipAddress
        return endpoint
    }
}

extension RemoteEndpoint {
    func clone() -> RemoteEndpoint {
        var endpoint = RemoteEndpoint()
        endpoint.hostName = self.hostName
        endpoint.port = self.port
        endpoint.service = self.service
        endpoint.ipAddress = self.ipAddress
        return endpoint
    }
}

#endif