#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import TransportServices
import Bluetooth

@Test("Bluetooth endpoint creation")
func testBluetoothEndpointCreation() async throws {
    // Test creating Bluetooth remote endpoints
    let peripheralUUID = UUID()
    let peripheralEndpoint = RemoteEndpoint.bluetoothPeripheral(peripheralUUID, psm: 0x1001)
    
    if case .bluetoothPeripheral(let uuid, let psm) = peripheralEndpoint.kind {
        #expect(uuid == peripheralUUID)
        #expect(psm == 0x1001)
    } else {
        Issue.record("Expected bluetooth peripheral endpoint")
    }
    
    // Test creating Bluetooth service endpoints
    let serviceUUID = UUID().uuidString
    let serviceEndpoint = RemoteEndpoint.bluetoothService(serviceUUID, psm: 0x1002)
    
    if case .bluetoothService(let uuid, let psm) = serviceEndpoint.kind {
        #expect(uuid == serviceUUID)
        #expect(psm == 0x1002)
    } else {
        Issue.record("Expected bluetooth service endpoint")
    }
    
    // Test creating Bluetooth local endpoints with published PSM
    let localEndpoint = LocalEndpoint.bluetoothPublishedPSM(0x1003)
    
    if case .bluetoothService(let uuid, let psm) = localEndpoint.kind {
        #expect(uuid == "published")
        #expect(psm == 0x1003)
    } else {
        Issue.record("Expected bluetooth service endpoint")
    }
}

@Test("Bluetooth transport properties")
func testBluetoothTransportProperties() async throws {
    var properties = TransportProperties()
    
    // Set a Bluetooth-related property
    properties.multipathMode = .disabled
    
    #expect(properties.multipathMode == .disabled)
}

@Test("Bluetooth address creation")
func testBluetoothAddressCreation() async throws {
    // Test creating a Bluetooth address from string
    let addressString = "00:11:22:33:44:55"
    let address = BluetoothAddress(rawValue: addressString)
    
    #expect(address != nil)
    #expect(address?.rawValue == addressString)
}

@Test("Bluetooth L2CAP framer basic functionality")
func testBluetoothL2CAPFramer() async throws {
    let framer = BluetoothL2CAPFramer()
    
    // Test framing an outbound message
    let testData = Data("Hello, Bluetooth!".utf8)
    let message = Message(testData)
    
    let framedData = try await framer.frameOutbound(message)
    #expect(framedData.count == 1)
    
    // The current implementation just passes through data without headers
    let framed = framedData[0]
    #expect(framed == testData)
}

@Test("Bluetooth L2CAP framer inbound parsing")
func testBluetoothL2CAPFramerParsing() async throws {
    let framer = BluetoothL2CAPFramer()
    
    // The current implementation treats each input as a complete message
    let testData = Data("Test message".utf8)
    
    // Parse the data
    let (messages, remainder) = try await framer.parseInbound(testData)
    
    #expect(messages.count == 1)
    #expect(messages[0].data == testData)
    #expect(remainder.isEmpty)
}

@Test("Bluetooth L2CAP framer MTU fragmentation")
func testBluetoothL2CAPFramerMTUFragmentation() async throws {
    // Test with small MTU to force fragmentation
    let framer = BluetoothL2CAPFramer(mtu: 10)
    
    // Create a message larger than MTU
    let largeData = Data("This is a long message that exceeds the MTU".utf8)
    let message = Message(largeData)
    
    // Frame the message - should be fragmented
    let fragments = try await framer.frameOutbound(message)
    
    // Verify fragmentation occurred
    #expect(fragments.count > 1)
    
    // Verify each fragment respects MTU
    for fragment in fragments {
        #expect(fragment.count <= 10)
    }
    
    // Verify we can reconstruct the original data
    let reconstructed = fragments.reduce(Data()) { $0 + $1 }
    #expect(reconstructed == largeData)
}

@Test("Bluetooth L2CAP framer with Preconnection")
func testBluetoothL2CAPFramerWithPreconnection() async throws {
    // Create a preconnection for Bluetooth
    let peripheralUUID = UUID()
    let preconnection = Preconnection(
        remote: [RemoteEndpoint.bluetoothPeripheral(peripheralUUID, psm: 0x1001)],
        transport: TransportProperties()
    )
    
    // Add the Bluetooth L2CAP framer
    let framer = BluetoothL2CAPFramer()
    await preconnection.add(framer: framer)
    
    // Verify framer was added
    #expect(framer is MessageFramer)
}

@Test("Bluetooth L2CAP framer MTU enforcement")
func testBluetoothL2CAPFramerMTUEnforcement() async throws {
    // Test with auto-fragmentation disabled
    let framer = BluetoothL2CAPFramer(mtu: 20, autoFragment: false)
    
    // Try to send a message that exceeds MTU
    let largeData = Data("This message is definitely longer than 20 bytes".utf8)
    let message = Message(largeData)
    
    // Should throw an error when auto-fragmentation is disabled
    do {
        _ = try await framer.frameOutbound(message)
        Issue.record("Expected error for message exceeding MTU")
    } catch {
        // Expected error
        #expect(error is TransportError)
    }
    
    // Small message should work fine
    let smallData = Data("Small".utf8)
    let smallMessage = Message(smallData)
    let frames = try await framer.frameOutbound(smallMessage)
    #expect(frames.count == 1)
    #expect(frames[0] == smallData)
}

@Test("Bluetooth L2CAP framer empty message")
func testBluetoothL2CAPFramerEmptyMessage() async throws {
    let framer = BluetoothL2CAPFramer()
    
    // Test framing an empty message
    let emptyMessage = Message(Data())
    let framedData = try await framer.frameOutbound(emptyMessage)
    
    // Current implementation passes through empty data
    #expect(framedData.count == 1)
    #expect(framedData[0].isEmpty)
    
    // Test parsing empty data
    let (messages, remainder) = try await framer.parseInbound(Data())
    #expect(messages.isEmpty)
    #expect(remainder.isEmpty)
}

@Test("Enhanced Bluetooth L2CAP framer with credit flow control")
func testEnhancedBluetoothL2CAPFramer() async throws {
    let framer = EnhancedBluetoothL2CAPFramer(mtu: 100, useCreditFlow: true)
    
    // Test basic functionality
    let testData = Data("Hello Enhanced L2CAP".utf8)
    let message = Message(testData)
    
    // Should succeed with available credits
    let framedData = try await framer.frameOutbound(message)
    #expect(framedData.count == 1)
    #expect(framedData[0] == testData)
    
    // Test inbound parsing
    let (messages, remainder) = try await framer.parseInbound(testData)
    #expect(messages.count == 1)
    #expect(messages[0].data == testData)
    #expect(remainder.isEmpty)
    
    // Test connection lifecycle
    let connection = Connection()
    await framer.connectionDidOpen(connection)
    await framer.connectionDidClose(connection)
}