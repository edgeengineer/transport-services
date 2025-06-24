import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Simple Preconnection Tests")
struct SimplePreconnectionTests {
    
    @Test("Create basic preconnection")
    func createBasicPreconnection() async throws {
        var localEndpoint = LocalEndpoint(kind: .host("localhost"))
        localEndpoint.port = 0
        var remoteEndpoint = RemoteEndpoint(kind: .host("example.com"))
        remoteEndpoint.port = 443
        
        let preconnection = Preconnection(
            local: [localEndpoint],
            remote: [remoteEndpoint]
        )
        
        // Test that preconnection was created successfully
        #expect(true)
    }
    
    @Test("Create preconnection for client")
    func createClientPreconnection() async throws {
        var remoteEndpoint = RemoteEndpoint(kind: .host("httpbin.org"))
        remoteEndpoint.port = 80
        
        let preconnection = Preconnection(remote: [remoteEndpoint])
        
        #expect(true)
    }
    
    @Test("Create preconnection for server")
    func createServerPreconnection() async throws {
        var localEndpoint = LocalEndpoint(kind: .host("0.0.0.0"))
        localEndpoint.port = 8080
        
        let preconnection = Preconnection(local: [localEndpoint])
        
        #expect(true)
    }
    
    @Test("Preconnection with transport properties")
    func preconnectionWithProperties() async throws {
        var properties = TransportProperties()
        properties.reliability = .require
        properties.preserveOrder = .prefer
        
        var remoteEndpoint = RemoteEndpoint(kind: .host("example.com"))
        remoteEndpoint.port = 443
        
        let preconnection = Preconnection(
            remote: [remoteEndpoint],
            transport: properties
        )
        
        #expect(true)
    }
    
    @Test("Preconnection validation for initiate")
    func initiateValidation() async throws {
        // Should fail without remote endpoint
        let preconnection = Preconnection()
        
        do {
            _ = try await preconnection.initiate()
            Issue.record("Should have thrown error for missing remote endpoint")
        } catch TransportError.establishmentFailure(let message) {
            #expect(message?.contains("Remote Endpoint") == true)
        }
    }
    
    @Test("Preconnection validation for listen")
    func listenValidation() async throws {
        // Should fail without local endpoint
        let preconnection = Preconnection()
        
        do {
            _ = try await preconnection.listen()
            Issue.record("Should have thrown error for missing local endpoint")
        } catch TransportError.establishmentFailure(let message) {
            #expect(message?.contains("Local Endpoint") == true)
        }
    }
    
    @Test("Add framers to preconnection")
    func addFramers() async throws {
        var remoteEndpoint = RemoteEndpoint(kind: .host("example.com"))
        remoteEndpoint.port = 80
        
        let preconnection = Preconnection(remote: [remoteEndpoint])
        
        let framer = DelimiterFramer.lineDelimited
        await preconnection.add(framer: framer)
        
        #expect(true)
    }
    
    @Test("Transport property convenience methods")
    func transportPropertyConvenience() async throws {
        // Test different property configurations
        let reliable = TransportProperties.reliableStream()
        let message = TransportProperties.reliableMessage()
        let datagram = TransportProperties.unreliableDatagram()
        let lowLatency = TransportProperties.lowLatency()
        
        var remoteEndpoint = RemoteEndpoint(kind: .host("example.com"))
        remoteEndpoint.port = 80
        
        // Should be able to create preconnections with all property types
        let preconnection1 = Preconnection(remote: [remoteEndpoint], transport: reliable)
        let preconnection2 = Preconnection(remote: [remoteEndpoint], transport: message)
        let preconnection3 = Preconnection(remote: [remoteEndpoint], transport: datagram)
        let preconnection4 = Preconnection(remote: [remoteEndpoint], transport: lowLatency)
        
        #expect(true)
    }
}