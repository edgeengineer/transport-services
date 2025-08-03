//
//  WindowsTest.swift
//  
//
//  Maximilian Alexander
//

#if os(Windows)
import TransportServices
import Foundation

@main
struct WindowsTest {
    static func main() async {
        print("Windows Transport Services Test")
        print("================================")
        
        // Initialize Windows platform
        let platform = WindowsPlatform()
        
        // Test 1: List network interfaces
        print("\n1. Network Interfaces:")
        do {
            let interfaces = try await platform.getAvailableInterfaces()
            for interface in interfaces {
                print("  - \(interface.name): \(interface.addresses.joined(separator: ", "))")
            }
        } catch {
            print("  Error: \(error)")
        }
        
        // Test 2: Create a TCP client preconnection
        print("\n2. Creating TCP Client Preconnection:")
        let remoteEndpoint = RemoteEndpoint(hostName: "example.com", port: 80)
        let properties = TransportProperties()
        properties.reliability = .require
        properties.ordering = .require
        
        let preconnection = WindowsPreconnection.client(
            to: remoteEndpoint,
            properties: properties
        )
        print("  Created preconnection to \(remoteEndpoint.hostName ?? "unknown"):\(remoteEndpoint.port ?? 0)")
        
        // Test 3: Create a TCP server preconnection
        print("\n3. Creating TCP Server Preconnection:")
        let localEndpoint = LocalEndpoint(ipAddress: "0.0.0.0", port: 8080)
        let serverPreconnection = WindowsPreconnection.server(
            on: localEndpoint,
            properties: properties
        )
        print("  Created server preconnection on \(localEndpoint.ipAddress ?? "any"):\(localEndpoint.port ?? 0)")
        
        // Test 4: Establish a connection (will likely fail but tests the code path)
        print("\n4. Testing Connection Establishment:")
        let testEndpoint = RemoteEndpoint(ipAddress: "127.0.0.1", port: 8080)
        let testPreconnection = WindowsPreconnection.client(
            to: testEndpoint,
            properties: properties
        )
        
        let connection = testPreconnection.establish { event in
            switch event {
            case .ready(let conn):
                print("  Connection ready: \(conn)")
            case .establishmentError(let conn, let reason):
                print("  Connection failed: \(reason)")
            default:
                break
            }
        }
        
        // Give it some time to attempt connection
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("\n5. Test Complete")
    }
}

#endif