//
//  WindowsCompat.swift
//  
//
//  Maximilian Alexander
//

#if os(Windows)
import WinSDK
import Foundation

/// Windows compatibility layer for networking
internal struct WindowsCompat {
    
    // MARK: - Type Aliases
    
    typealias SOCKET = WinSDK.SOCKET
    typealias DWORD = WinSDK.DWORD
    typealias LPOVERLAPPED = UnsafeMutablePointer<WinSDK.OVERLAPPED>
    
    // MARK: - Winsock Initialization
    
    nonisolated(unsafe) private static var wsaInitialized = false
    private static let wsaLock = NSLock()
    
    /// Initialize Winsock
    static func initializeWinsock() {
        wsaLock.lock()
        defer { wsaLock.unlock() }
        
        guard !wsaInitialized else { return }
        
        var wsaData = WSADATA()
        let version = WORD(2) | (WORD(2) << 8) // MAKEWORD(2, 2) - Request Winsock 2.2
        let result = WSAStartup(version, &wsaData)
        
        if result != 0 {
            fatalError("WSAStartup failed: \(result)")
        }
        
        wsaInitialized = true
        
        // Register cleanup on exit
        atexit {
            WSACleanup()
        }
    }
    
    // MARK: - Socket Constants
    
    static let SOCK_STREAM = Int32(1)     // TCP
    static let SOCK_DGRAM = Int32(2)      // UDP
    static let IPPROTO_TCP = Int32(6)
    static let IPPROTO_UDP = Int32(17)
    
    static let AF_INET = Int32(2)         // IPv4
    static let AF_INET6 = Int32(23)       // IPv6
    
    static let INADDR_ANY = UInt32(0)
    
    // Socket options
    static let SOL_SOCKET = Int32(0xffff)
    static let SO_REUSEADDR = Int32(0x0004)
    static let SO_KEEPALIVE = Int32(0x0008)
    static let SO_ERROR = Int32(0x1007)
    
    static let TCP_NODELAY = Int32(0x0001)
    
    // Shutdown options
    static let SD_RECEIVE = Int32(0)
    static let SD_SEND = Int32(1)
    static let SD_BOTH = Int32(2)
    
    // MARK: - Error Handling
    
    /// Get last Windows socket error
    static func getLastSocketError() -> Int32 {
        return WSAGetLastError()
    }
    
    /// Get error string for a Windows error code
    static func errorString(_ error: Int32) -> String {
        var buffer = [WCHAR](repeating: 0, count: 256)
        let flags = DWORD(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS)
        
        let result = FormatMessageW(
            flags,
            nil,
            DWORD(error),
            0,
            &buffer,
            DWORD(buffer.count),
            nil
        )
        
        if result > 0 {
            // Convert WCHAR buffer to String
            // Fix dangling buffer pointer warning
            return buffer.withUnsafeBufferPointer { bufferPointer in
                let truncated = bufferPointer.prefix(Int(result))
                return String(decoding: truncated, as: UTF16.self)
            }
        } else {
            return "Unknown error: \(error)"
        }
    }
    
    // MARK: - Socket Creation
    
    /// Create a socket
    static func socket(family: Int32, type: Int32, proto: Int32) -> SOCKET? {
        initializeWinsock()
        
        let sock = WinSDK.socket(family, type, proto)
        if sock == INVALID_SOCKET {
            return nil
        }
        return sock
    }
    
    /// Set socket to non-blocking mode
    static func setNonBlocking(_ socket: SOCKET) -> Bool {
        var mode: u_long = 1
        return ioctlsocket(socket, FIONBIO, &mode) == 0
    }
    
    // MARK: - Address Conversion
    
    /// Convert sockaddr_in to Swift structure
    static func createSockaddrIn(address: String?, port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_family = ADDRESS_FAMILY(AF_INET)
        addr.sin_port = htons(port)
        
        if let address = address {
            inet_pton(AF_INET, address, &addr.sin_addr)
        } else {
            addr.sin_addr.S_un.S_addr = INADDR_ANY
        }
        
        return addr
    }
    
    /// Convert sockaddr_in6 to Swift structure
    static func createSockaddrIn6(address: String?, port: UInt16) -> sockaddr_in6 {
        var addr = sockaddr_in6()
        addr.sin6_family = ADDRESS_FAMILY(AF_INET6)
        addr.sin6_port = htons(port)
        
        if let address = address {
            inet_pton(AF_INET6, address, &addr.sin6_addr)
        } else {
            // IN6ADDR_ANY_INIT
            addr.sin6_addr = in6_addr()
        }
        
        return addr
    }
    
    /// Convert IP address to string
    static func ipToString(family: Int32, addr: UnsafeRawPointer) -> String? {
        let bufferSize = family == AF_INET ? Int(INET_ADDRSTRLEN) : Int(INET6_ADDRSTRLEN)
        var buffer = [CChar](repeating: 0, count: bufferSize)
        
        if inet_ntop(family, addr, &buffer, Int(bufferSize)) != nil {
            // Find null terminator
            let validLength = buffer.firstIndex(of: 0) ?? buffer.count
            let uint8Buffer = buffer[..<validLength].map { UInt8(bitPattern: $0) }
            return String(decoding: uint8Buffer, as: UTF8.self)
        }
        return nil
    }
    
    // MARK: - DNS Resolution
    
    /// Resolve hostname to addresses
    static func resolveHostname(_ hostname: String, type: Int32 = SOCK_STREAM) async throws -> [String] {
        initializeWinsock()
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC  // Both IPv4 and IPv6
                hints.ai_socktype = type
                
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, nil, &hints, &result)
                
                guard status == 0 else {
                    continuation.resume(throwing: WindowsTransportError.resolutionFailed(status))
                    return
                }
                
                defer { freeaddrinfo(result) }
                
                var addresses: [String] = []
                var current = result
                
                while let addr = current {
                    if addr.pointee.ai_family == AF_INET {
                        addr.pointee.ai_addr!.withMemoryRebound(
                            to: sockaddr_in.self,
                            capacity: 1
                        ) { ptr in
                            if let ip = ipToString(family: AF_INET, addr: &ptr.pointee.sin_addr) {
                                addresses.append(ip)
                            }
                        }
                    } else if addr.pointee.ai_family == AF_INET6 {
                        addr.pointee.ai_addr!.withMemoryRebound(
                            to: sockaddr_in6.self,
                            capacity: 1
                        ) { ptr in
                            if let ip = ipToString(family: AF_INET6, addr: &ptr.pointee.sin6_addr) {
                                addresses.append(ip)
                            }
                        }
                    }
                    
                    current = addr.pointee.ai_next
                }
                
                continuation.resume(returning: addresses)
            }
        }
    }
    
    // MARK: - Network Interface Discovery
    
    /// Get available network interfaces
    static func getNetworkInterfaces() throws -> [NetworkInterface] {
        initializeWinsock()
        
        var interfaces: [NetworkInterface] = []
        
        // Use GetAdaptersAddresses to enumerate network interfaces
        var bufferSize: ULONG = 15000
        var buffer = [UInt8](repeating: 0, count: Int(bufferSize))
        
        let flags = DWORD(GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST)
        
        let result = buffer.withUnsafeMutableBytes { ptr in
            GetAdaptersAddresses(
                ULONG(AF_UNSPEC),
                flags,
                nil,
                ptr.bindMemory(to: IP_ADAPTER_ADDRESSES.self).baseAddress,
                &bufferSize
            )
        }
        
        if result != ERROR_SUCCESS {
            throw WindowsTransportError.interfaceEnumerationFailed(Int32(result))
        }
        
        // Parse the adapter information
        buffer.withUnsafeMutableBytes { ptr in
            var adapter: UnsafeMutablePointer<IP_ADAPTER_ADDRESSES>? = ptr.bindMemory(to: IP_ADAPTER_ADDRESSES.self).baseAddress
            
            while let currentAdapter = adapter {
                let name = String(cString: currentAdapter.pointee.AdapterName)
                // Convert Windows WCHAR string to Swift String
                var friendlyName = ""
                if let ptr = currentAdapter.pointee.FriendlyName {
                    var friendlyNameBuffer: [UInt16] = []
                    var currentPtr = ptr
                    while currentPtr.pointee != 0 {
                        friendlyNameBuffer.append(currentPtr.pointee)
                        currentPtr = currentPtr.advanced(by: 1)
                    }
                    friendlyName = String(decoding: friendlyNameBuffer, as: UTF16.self)
                }
                
                // Determine interface type
                let type: NetworkInterface.InterfaceType
                switch currentAdapter.pointee.IfType {
                case IF_TYPE_ETHERNET_CSMACD:
                    type = .ethernet
                case IF_TYPE_IEEE80211:
                    type = .wifi
                case IF_TYPE_SOFTWARE_LOOPBACK:
                    type = .loopback
                default:
                    type = .other
                }
                
                // Get IP addresses
                var addresses: [SocketAddress] = []
                var unicastAddr = currentAdapter.pointee.FirstUnicastAddress
                
                while let addr = unicastAddr {
                    let sockaddr = addr.pointee.Address.lpSockaddr
                    
                    if sockaddr?.pointee.sa_family == ADDRESS_FAMILY(AF_INET) {
                        sockaddr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                            if let ip = ipToString(family: AF_INET, addr: &ptr.pointee.sin_addr) {
                                let port = ntohs(ptr.pointee.sin_port)
                                addresses.append(.ipv4(address: ip, port: port))
                            }
                        }
                    } else if sockaddr?.pointee.sa_family == ADDRESS_FAMILY(AF_INET6) {
                        sockaddr!.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                            if let ip = ipToString(family: AF_INET6, addr: &ptr.pointee.sin6_addr) {
                                let port = ntohs(ptr.pointee.sin6_port)
                                addresses.append(.ipv6(address: ip, port: port, scopeId: ptr.pointee.sin6_scope_id))
                            }
                        }
                    }
                    
                    unicastAddr = addr.pointee.Next
                }
                
                // Get interface index and status
                let interfaceIndex = Int(currentAdapter.pointee.IfIndex)
                let isUp = DWORD(currentAdapter.pointee.OperStatus.rawValue) == IfOperStatusUp
                
                let networkInterface = NetworkInterface(
                    name: friendlyName.isEmpty ? name : friendlyName,
                    index: interfaceIndex,
                    type: type,
                    addresses: addresses,
                    isUp: isUp,
                    supportsMulticast: true  // TODO: Check actual multicast support
                )
                interfaces.append(networkInterface)
                
                adapter = currentAdapter.pointee.Next
            }
        }
        
        return interfaces
    }
}

/// Windows-specific transport errors
enum WindowsTransportError: Error, LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case acceptFailed(Int32)
    case listenFailed(Int32)
    case invalidAddress
    case missingPort
    case noAddressSpecified
    case resolutionFailed(Int32)
    case interfaceEnumerationFailed(Int32)
    case iocpError(Int32)
    
    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let error):
            return "Failed to create socket: \(WindowsCompat.errorString(error))"
        case .bindFailed(let error):
            return "Failed to bind socket: \(WindowsCompat.errorString(error))"
        case .connectFailed(let error):
            return "Failed to connect: \(WindowsCompat.errorString(error))"
        case .sendFailed(let error):
            return "Failed to send data: \(WindowsCompat.errorString(error))"
        case .receiveFailed(let error):
            return "Failed to receive data: \(WindowsCompat.errorString(error))"
        case .acceptFailed(let error):
            return "Failed to accept connection: \(WindowsCompat.errorString(error))"
        case .listenFailed(let error):
            return "Failed to listen: \(WindowsCompat.errorString(error))"
        case .invalidAddress:
            return "Invalid IP address format"
        case .missingPort:
            return "Port number is required"
        case .noAddressSpecified:
            return "No address specified for connection"
        case .resolutionFailed(let error):
            return "Failed to resolve hostname: error \(error)"
        case .interfaceEnumerationFailed(let error):
            return "Failed to enumerate network interfaces: \(WindowsCompat.errorString(error))"
        case .iocpError(let error):
            return "IOCP error: \(WindowsCompat.errorString(error))"
        }
    }
}

// MARK: - Helper Constants

private let FORMAT_MESSAGE_FROM_SYSTEM = DWORD(0x00001000)
private let FORMAT_MESSAGE_IGNORE_INSERTS = DWORD(0x00000200)

private let GAA_FLAG_INCLUDE_PREFIX = DWORD(0x0010)
private let GAA_FLAG_SKIP_ANYCAST = DWORD(0x0002)
private let GAA_FLAG_SKIP_MULTICAST = DWORD(0x0004)

private let IF_TYPE_ETHERNET_CSMACD = DWORD(6)
private let IF_TYPE_IEEE80211 = DWORD(71)
private let IF_TYPE_SOFTWARE_LOOPBACK = DWORD(24)

private let IfOperStatusUp = DWORD(1)

#endif