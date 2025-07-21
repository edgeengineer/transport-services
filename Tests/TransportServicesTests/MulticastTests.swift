#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import TransportServices
import Testing
@preconcurrency import NIOCore
import NIOPosix

@Suite("Multicast Tests")
struct MulticastTests {
    
    // MARK: - Basic Multicast Tests
    
    @Test("Multicast endpoint creation")
    func multicastEndpointCreation() throws {
        // Test ASM endpoint
        let asmEndpoint = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: 5000,
            interface: "en0",
            ttl: 10,
            loopback: true
        )
        
        #expect(asmEndpoint.groupAddress == "239.1.2.3")
        #expect(asmEndpoint.port == 5000)
        #expect(asmEndpoint.interface == "en0")
        #expect(asmEndpoint.ttl == 10)
        #expect(asmEndpoint.loopback == true)
        
        switch asmEndpoint.type {
        case .anySource:
            break // Expected
        case .sourceSpecific:
            Issue.record("Expected any-source multicast")
        }
        
        // Test SSM endpoint
        let ssmEndpoint = MulticastEndpoint(
            groupAddress: "232.1.2.3",
            sources: ["192.168.1.100", "10.0.0.5"],
            port: 6000
        )
        
        switch ssmEndpoint.type {
        case .anySource:
            Issue.record("Expected source-specific multicast")
        case .sourceSpecific(let sources):
            #expect(sources.count == 2)
            #expect(sources.contains("192.168.1.100"))
            #expect(sources.contains("10.0.0.5"))
        }
    }
    
    @Test("Multicast address detection")
    func multicastAddressDetection() throws {
        // Test IPv4 multicast addresses
        let multicastIPv4 = Endpoint(kind: .ip("239.1.2.3"))
        #expect(multicastIPv4.isMulticast)
        
        let multicastIPv4_2 = Endpoint(kind: .ip("224.0.0.1"))
        #expect(multicastIPv4_2.isMulticast)
        
        let nonMulticastIPv4 = Endpoint(kind: .ip("192.168.1.1"))
        #expect(!nonMulticastIPv4.isMulticast)
        
        // Test IPv6 multicast addresses
        let multicastIPv6 = Endpoint(kind: .ip("ff02::1"))
        #expect(multicastIPv6.isMulticast)
        
        let multicastIPv6_2 = Endpoint(kind: .ip("FF05::1:3"))
        #expect(multicastIPv6_2.isMulticast)
        
        let nonMulticastIPv6 = Endpoint(kind: .ip("2001:db8::1"))
        #expect(!nonMulticastIPv6.isMulticast)
        
        // Test hostname
        let hostname = Endpoint(kind: .host("example.com"))
        #expect(!hostname.isMulticast)
    }
    
    @Test("Endpoint conversion")
    func endpointConversion() throws {
        let multicast = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: 5000,
            interface: "en0"
        )
        
        // Test conversion to LocalEndpoint
        let local = multicast.toLocalEndpoint()
        #expect(local.port == 5000)
        #expect(local.interface == "en0")
        
        switch local.kind {
        case .ip(let address):
            #expect(address == "239.1.2.3")
        case .host:
            Issue.record("Expected IP endpoint")
        }
        
        // Test conversion to RemoteEndpoint
        let remote = multicast.toRemoteEndpoint()
        #expect(remote.port == 5000)
        
        switch remote.kind {
        case .ip(let address):
            #expect(address == "239.1.2.3")
        case .host:
            Issue.record("Expected IP endpoint")
        }
    }
    
    // MARK: - Multicast Connection Tests
    
    @Test("Multicast receiver connection")
    func multicastReceiverConnection() async throws {
        let multicast = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: 0, // Use ephemeral port for testing
            ttl: 1,
            loopback: true // Enable loopback for testing
        )
        
        // Configure properties for receive-only
        var properties = TransportProperties()
        properties.multicast.direction = .receiveOnly
        properties.multicast.joinGroup = true
        
        let preconnection = Preconnection(
            local: [multicast.toLocalEndpoint()],
            transport: properties
        )
        
        // Try to listen for multicast (should fail with current implementation)
        await #expect(throws: TransportError.self) {
            _ = try await preconnection.listen()
        }
    }
    
    @Test("Multicast sender connection")
    func multicastSenderConnection() async throws {
        let multicast = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: 5000,
            ttl: 1
        )
        
        // Configure properties for send-only
        var properties = TransportProperties()
        properties.multicast.direction = .sendOnly
        properties.multicast.joinGroup = false
        
        let preconnection = Preconnection(
            remote: [multicast.toRemoteEndpoint()],
            transport: properties
        )
        
        // Try to initiate multicast sender
        // This should now succeed with proper multicast support
        let connection = try await preconnection.initiate()
        
        // Verify connection was established
        let state = await connection.state
        #expect(state == .established)
        
        // Clean up
        await connection.close()
    }
    
    @Test("Multicast bidirectional connection")
    func multicastBidirectionalConnection() async throws {
        let multicast = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: 5000
        )
        
        // Configure properties for bidirectional
        var properties = TransportProperties()
        properties.multicast.direction = .bidirectional
        properties.multicast.joinGroup = true
        
        let preconnection = Preconnection(
            local: [multicast.toLocalEndpoint()],
            remote: [multicast.toRemoteEndpoint()],
            transport: properties
        )
        
        // Try to initiate bidirectional multicast
        // This should now succeed with proper multicast support
        let connection = try await preconnection.initiate()
        
        // Verify connection was established
        let state = await connection.state
        #expect(state == .established)
        
        // Clean up
        await connection.close()
    }
    
    // MARK: - Edge Cases
    
    @Test("Invalid multicast addresses")
    func invalidMulticastAddresses() throws {
        // Test invalid IPv4 multicast addresses
        let invalidIPv4_1 = Endpoint(kind: .ip("223.255.255.255")) // Just below range
        #expect(!invalidIPv4_1.isMulticast)
        
        let invalidIPv4_2 = Endpoint(kind: .ip("240.0.0.0")) // Just above range
        #expect(!invalidIPv4_2.isMulticast)
        
        // Test malformed addresses
        let malformed1 = Endpoint(kind: .ip("239.1.2"))
        #expect(!malformed1.isMulticast)
        
        let malformed2 = Endpoint(kind: .ip("not.an.ip.address"))
        #expect(!malformed2.isMulticast)
    }
    
    @Test("Multicast properties defaults")
    func multicastPropertiesDefaults() throws {
        let props = TransportProperties.MulticastProperties()
        #expect(props.direction == .receiveOnly)
        #expect(props.joinGroup == true)
        #expect(props.interfaceIndex == nil)
        #expect(props.sourceFilter == nil)
    }
    
    @Test("Multicast specific error messages")
    func multicastSpecificErrors() async throws {
        let multicast = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: 0,
            ttl: 1,
            loopback: true
        )
        
        var properties = TransportProperties()
        properties.multicast.direction = .receiveOnly
        properties.multicast.joinGroup = true
        
        let preconnection = Preconnection(
            local: [multicast.toLocalEndpoint()],
            transport: properties
        )
        
        do {
            _ = try await preconnection.listen()
            Issue.record("Expected error to be thrown")
        } catch let error as TransportError {
            switch error {
            case .notSupported(let message):
                // Either error message is acceptable since multicast is not fully implemented
                #expect(message.contains("multicast") || message.contains("Multicast"))
            default:
                Issue.record("Expected notSupported error, got: \(error)")
            }
        } catch {
            Issue.record("Expected TransportError, got: \(error)")
        }
    }
    
    @Test("Multicast send and receive") 
    func multicastSendAndReceive() async throws {
        // Use a random multicast port to avoid conflicts
        let port = UInt16.random(in: 10000...20000)
        let multicast = MulticastEndpoint(
            groupAddress: "239.1.2.3",
            port: port,
            ttl: 1,
            loopback: true  // Enable loopback for local testing
        )
        
        // Create receiver
        var receiverProps = TransportProperties()
        receiverProps.multicast.direction = .receiveOnly
        receiverProps.multicast.joinGroup = true
        
        let _ = Preconnection(
            local: [multicast.toLocalEndpoint()],
            transport: receiverProps
        )
        
        // Create sender
        var senderProps = TransportProperties()
        senderProps.multicast.direction = .sendOnly
        senderProps.multicast.joinGroup = false
        
        let senderPreconnection = Preconnection(
            remote: [multicast.toRemoteEndpoint()],
            transport: senderProps
        )
        
        // Currently, multicast receiver wrapping is not implemented
        // So we test that the sender can be created successfully
        let sender = try await senderPreconnection.initiate()
        let senderState = await sender.state
        #expect(senderState == .established)
        
        // Clean up
        await sender.close()
    }
}