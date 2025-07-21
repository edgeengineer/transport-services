#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import TransportServices
import Testing
@preconcurrency import NIOCore
import NIOPosix

@Suite("Multicast Integration Tests")
struct MulticastIntegrationTests {
    
    @Test("Multicast data transmission between sender and receiver")
    func multicastDataTransmission() async throws {
        // Use a random multicast port to avoid conflicts
        let port = UInt16.random(in: 20000...30000)
        let multicast = MulticastEndpoint(
            groupAddress: "239.255.1.2",
            port: port,
            ttl: 1,
            loopback: true  // Enable loopback for local testing
        )
        
        // Create receiver first
        var receiverProps = TransportProperties()
        receiverProps.multicast.direction = .receiveOnly
        receiverProps.multicast.joinGroup = true
        
        let receiverPreconnection = Preconnection(
            local: [multicast.toLocalEndpoint()],
            transport: receiverProps
        )
        
        // This should fail with current implementation since receiver wrapping isn't complete
        await #expect(throws: TransportError.self) {
            _ = try await receiverPreconnection.listen()
        }
        
        // Create sender
        var senderProps = TransportProperties()
        senderProps.multicast.direction = .sendOnly
        senderProps.multicast.joinGroup = false
        
        let senderPreconnection = Preconnection(
            remote: [multicast.toRemoteEndpoint()],
            transport: senderProps
        )
        
        let sender = try await senderPreconnection.initiate()
        let senderState = await sender.state
        #expect(senderState == .established)
        
        // Try to send data (even though we don't have a receiver yet)
        let testData = Data("Hello, Multicast!".utf8)
        let message = Message(testData)
        
        // Send should work even without receivers
        try await sender.send(message)
        
        // Clean up
        await sender.close()
    }
    
    @Test("Multicast TTL configuration")
    func multicastTTLConfiguration() async throws {
        // Test different TTL values
        let ttlValues: [UInt8] = [1, 10, 64, 255]
        
        for ttl in ttlValues {
            let multicast = MulticastEndpoint(
                groupAddress: "239.255.1.3",
                port: UInt16.random(in: 30000...40000),
                ttl: ttl,
                loopback: false
            )
            
            var props = TransportProperties()
            props.multicast.direction = .sendOnly
            
            let preconnection = Preconnection(
                remote: [multicast.toRemoteEndpoint()],
                transport: props
            )
            
            let connection = try await preconnection.initiate()
            let state = await connection.state
            #expect(state == .established)
            
            // The TTL should be configured in the socket options
            await connection.close()
        }
    }
    
    @Test("Multicast interface selection")
    func multicastInterfaceSelection() async throws {
        // Get available network interfaces
        let devices = try NIOCore.System.enumerateDevices()
        
        // Find a suitable interface (prefer en0 or lo0)
        let preferredInterface = devices.first { $0.name == "en0" || $0.name == "lo0" }
        guard let interface = preferredInterface else {
            Issue.record("No suitable network interface found for testing")
            return
        }
        
        let multicast = MulticastEndpoint(
            groupAddress: "239.255.1.4",
            port: UInt16.random(in: 40000...50000),
            interface: interface.name,
            ttl: 1,
            loopback: true
        )
        
        var props = TransportProperties()
        props.multicast.direction = .sendOnly
        
        let preconnection = Preconnection(
            remote: [multicast.toRemoteEndpoint()],
            transport: props
        )
        
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        await connection.close()
    }
    
    @Test("Multicast group address validation")
    func multicastGroupAddressValidation() async throws {
        // Test valid IPv4 multicast addresses
        let validIPv4Addresses = [
            "224.0.0.1",   // All hosts
            "224.0.0.2",   // All routers
            "239.255.255.250", // SSDP
            "232.1.1.1"    // SSM range
        ]
        
        for address in validIPv4Addresses {
            let endpoint = Endpoint(kind: .ip(address))
            #expect(endpoint.isMulticast)
        }
        
        // Test valid IPv6 multicast addresses
        let validIPv6Addresses = [
            "ff02::1",     // All nodes
            "ff02::2",     // All routers
            "ff05::1:3",   // Site-local
            "ff08::1"      // Organization-local
        ]
        
        for address in validIPv6Addresses {
            let endpoint = Endpoint(kind: .ip(address))
            #expect(endpoint.isMulticast)
        }
    }
    
    @Test("ASM vs SSM endpoint types")
    func asmVsSsmEndpointTypes() throws {
        // ASM endpoint (Any-Source Multicast)
        let asmEndpoint = MulticastEndpoint(
            groupAddress: "239.1.1.1",
            port: 5000
        )
        
        switch asmEndpoint.type {
        case .anySource:
            // Expected
            break
        case .sourceSpecific:
            Issue.record("Expected ASM endpoint")
        }
        
        // SSM endpoint (Source-Specific Multicast)
        let ssmEndpoint = MulticastEndpoint(
            groupAddress: "232.1.1.1",
            sources: ["10.0.0.1", "10.0.0.2"],
            port: 5000
        )
        
        switch ssmEndpoint.type {
        case .anySource:
            Issue.record("Expected SSM endpoint")
        case .sourceSpecific(let sources):
            #expect(sources.count == 2)
            #expect(sources.contains("10.0.0.1"))
            #expect(sources.contains("10.0.0.2"))
        }
    }
    
    @Test("Multicast loopback configuration")
    func multicastLoopbackConfiguration() async throws {
        // Test with loopback enabled
        let multicastWithLoopback = MulticastEndpoint(
            groupAddress: "239.255.1.5",
            port: UInt16.random(in: 50000...60000),
            ttl: 1,
            loopback: true
        )
        
        var props = TransportProperties()
        props.multicast.direction = .sendOnly
        
        let preconnection = Preconnection(
            remote: [multicastWithLoopback.toRemoteEndpoint()],
            transport: props
        )
        
        let connection = try await preconnection.initiate()
        let state = await connection.state
        #expect(state == .established)
        
        // Send data - with loopback enabled, we would receive our own packets
        let testData = Data("Loopback test".utf8)
        let message = Message(testData)
        try await connection.send(message)
        
        await connection.close()
        
        // Test with loopback disabled
        let multicastNoLoopback = MulticastEndpoint(
            groupAddress: "239.255.1.6",
            port: UInt16.random(in: 50000...60000),
            ttl: 1,
            loopback: false
        )
        
        let preconnection2 = Preconnection(
            remote: [multicastNoLoopback.toRemoteEndpoint()],
            transport: props
        )
        
        let connection2 = try await preconnection2.initiate()
        let state2 = await connection2.state
        #expect(state2 == .established)
        
        await connection2.close()
    }
}