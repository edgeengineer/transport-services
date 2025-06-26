import TransportServices
import Foundation

/// Bluetooth Example
///
/// This example demonstrates:
/// - Bluetooth service discovery
/// - Establishing Bluetooth L2CAP connections
/// - Sending and receiving messages over Bluetooth
/// - Using the Bluetooth L2CAP framer

@main
struct BluetoothExample {
    static func main() async {
        // Run central and peripheral examples
        async let central = runBluetoothCentral()
        async let peripheral = runBluetoothPeripheral()
        
        let _ = await (central, peripheral)
    }
    
    /// Run as a Bluetooth central (client)
    static func runBluetoothCentral() async {
        print("\n=== Bluetooth Central (Client) ===")
        
        do {
            // Create a Bluetooth endpoint for a specific service
            let serviceUUID = "12345678-1234-5678-1234-567812345678"
            var remoteEndpoint = RemoteEndpoint(kind: .bluetoothService(serviceUUID: serviceUUID, psm: nil))
            
            // Create transport properties for Bluetooth
            var properties = TransportProperties()
            // Force Bluetooth by disabling other protocols
            properties.reliability = .prohibit // This will exclude TCP
            properties.preserveMsgBoundaries = .require // This will favor Bluetooth
            
            // Add the Bluetooth L2CAP framer
            let _ = BluetoothL2CAPFramer(mtu: 512)
            
            // Create preconnection
            let preconnection = Preconnection(
                remote: [remoteEndpoint],
                transport: properties,
                security: SecurityParameters()
            )
            
            // In a real implementation, the framer would be added here
            // preconnection.addFramer(bluetoothFramer)
            
            print("Discovering Bluetooth service: \(serviceUUID)")
            
            // In a real app, you'd use service discovery here
            // For this example, we'll simulate finding a peripheral
            try await Task.sleep(for: .seconds(2))
            
            // Simulate finding a peripheral and updating the endpoint
            let peripheralUUID = UUID()
            remoteEndpoint = RemoteEndpoint(kind: .bluetoothPeripheral(peripheralUUID: peripheralUUID, psm: 0x1001))
            
            print("Found peripheral: \(peripheralUUID)")
            print("Connecting to Bluetooth peripheral...")
            
            // Establish connection
            let connection = try await preconnection.initiate()
            print("Connected via Bluetooth!")
            
            // Send a message
            let request = Message("Hello from Bluetooth Central!".data(using: .utf8)!)
            try await connection.send(request)
            print("Sent: Hello from Bluetooth Central!")
            
            // Receive response
            let response = try await connection.receive()
            if let responseText = String(data: response.data, encoding: .utf8) {
                print("Received: \(responseText)")
            }
            
            // Send a large message to test fragmentation
            let largeData = Data(repeating: 0x42, count: 1500) // Larger than typical MTU
            let largeMessage = Message(largeData)
            try await connection.send(largeMessage)
            print("Sent large message (\(largeData.count) bytes)")
            
            // Close connection
            await connection.close()
            print("Central: Connection closed")
            
        } catch {
            print("Central error: \(error)")
        }
    }
    
    /// Run as a Bluetooth peripheral (server)
    static func runBluetoothPeripheral() async {
        print("\n=== Bluetooth Peripheral (Server) ===")
        
        do {
            // Create a local Bluetooth endpoint
            let serviceUUID = "12345678-1234-5678-1234-567812345678"
            let localEndpoint = LocalEndpoint(kind: .bluetoothService(serviceUUID: serviceUUID, psm: 0x1001))
            // In a real implementation, you'd specify the Bluetooth interface
            
            // Create transport properties for Bluetooth
            var properties = TransportProperties()
            // Force Bluetooth by disabling other protocols
            properties.reliability = .prohibit // This will exclude TCP
            properties.preserveMsgBoundaries = .require // This will favor Bluetooth
            
            // Create preconnection and listener
            let preconnection = Preconnection(
                local: [localEndpoint],
                transport: properties,
                security: SecurityParameters()
            )
            
            let listener = try await preconnection.listen()
            
            print("Advertising Bluetooth service: \(serviceUUID)")
            
            // Accept incoming connections
            print("Waiting for connections...")
            
            for try await connection in listener.newConnections {
                print("Peripheral: Accepted connection")
                
                // Handle connection in a separate task
                Task {
                    do {
                        // Add Bluetooth framer to the connection
                        // (In a real implementation, this would be automatic)
                        
                        // Receive message
                        let message = try await connection.receive()
                        if let messageText = String(data: message.data, encoding: .utf8) {
                            print("Peripheral received: \(messageText)")
                        }
                        
                        // Send response
                        let response = Message("Hello from Bluetooth Peripheral!".data(using: .utf8)!)
                        try await connection.send(response)
                        print("Peripheral sent response")
                        
                        // Receive large message
                        let largeMessage = try await connection.receive()
                        print("Peripheral received large message (\(largeMessage.data.count) bytes)")
                        
                        // Wait a bit before closing
                        try await Task.sleep(for: .seconds(1))
                        
                        await connection.close()
                        print("Peripheral: Connection closed")
                    } catch {
                        print("Peripheral connection error: \(error)")
                    }
                }
                
                // For this example, only accept one connection
                break
            }
            
            await listener.stop()
            
        } catch {
            print("Peripheral error: \(error)")
        }
    }
}

// MARK: - Bluetooth Discovery Example

extension BluetoothExample {
    /// Demonstrates Bluetooth service discovery
    static func demonstrateDiscovery() async {
        print("\n=== Bluetooth Discovery Example ===")
        
        // Create a discoverable service
        let service = DiscoverableService(
            type: "_myservice._bluetooth",
            domain: "local",
            metadata: [
                "version": "1.0",
                "psm": "0x1001"
            ],
            transport: .bluetooth
        )
        
        // In a real implementation, this would:
        // 1. Use the BluetoothDiscoveryProvider to advertise
        // 2. Scan for other Bluetooth services
        // 3. Handle discovery events
        
        print("Service configured for Bluetooth discovery:")
        print("  Type: \(service.type)")
        print("  Transport: \(service.transport)")
    }
}

// MARK: - Bluetooth Channel Options Example

extension BluetoothExample {
    /// Demonstrates Bluetooth-specific channel options
    static func demonstrateBluetoothOptions() async {
        print("\n=== Bluetooth Channel Options ===")
        
        // Create transport properties with Bluetooth-specific options
        var properties = TransportProperties()
        
        // Configure for Bluetooth
        properties.reliability = .prohibit // Exclude TCP
        properties.preserveMsgBoundaries = .require // Favor message-oriented protocols
        
        // Use enhanced L2CAP framer with credit-based flow control
        let _ = EnhancedBluetoothL2CAPFramer(
            mtu: 512,
            useCreditFlow: true
        )
        
        print("Bluetooth options configured:")
        print("  Reliability: Prohibited (excludes TCP)")
        print("  Message boundaries: Required")
        print("  Framer: Enhanced L2CAP with credit flow")
    }
}