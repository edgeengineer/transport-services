import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Endpoint Tests")
struct EndpointTests {
    
    @Test("Endpoint creation with hostname")
    func hostnameEndpoint() {
        var endpoint = Endpoint(kind: .host("example.com"))
        endpoint.port = 443
        endpoint.service = "https"
        
        #expect(endpoint.port == 443)
        #expect(endpoint.service == "https")
        
        // Test description
        let description = endpoint.description
        #expect(description == "example.com:443")
    }
    
    @Test("Endpoint creation with IP address")
    func ipEndpoint() {
        var endpoint = Endpoint(kind: .ip("192.0.2.1"))
        endpoint.port = 8080
        
        #expect(endpoint.port == 8080)
        #expect(endpoint.description == "192.0.2.1:8080")
        
        // IPv6 endpoint
        var ipv6Endpoint = Endpoint(kind: .ip("2001:db8::1"))
        ipv6Endpoint.port = 443
        
        #expect(ipv6Endpoint.description == "[2001:db8::1]:443")
    }
    
    @Test("Endpoint with interface")
    func endpointWithInterface() {
        var endpoint = Endpoint(kind: .ip("fe80::1"))
        endpoint.interface = "en0"
        endpoint.port = 80
        
        #expect(endpoint.interface == "en0")
        #expect(endpoint.description == "[fe80::1]:80%en0")
    }
    
    @Test("Endpoint convenience methods")
    func endpointConvenience() {
        // Loopback endpoint
        let loopback = Endpoint.loopback(port: 3000)
        #expect(loopback.port == 3000)
        if case .ip(let address) = loopback.kind {
            #expect(address == "127.0.0.1")
        } else {
            Issue.record("Expected IP endpoint")
        }
        
        // IPv6 loopback
        let loopbackV6 = Endpoint.loopback(port: 3000, ipv6: true)
        if case .ip(let address) = loopbackV6.kind {
            #expect(address == "::1")
        } else {
            Issue.record("Expected IPv6 endpoint")
        }
        
        // Any interface endpoint
        let anyInterface = Endpoint.any(port: 8080)
        #expect(anyInterface.port == 8080)
        if case .ip(let address) = anyInterface.kind {
            #expect(address == "0.0.0.0")
        } else {
            Issue.record("Expected any interface endpoint")
        }
    }
    
    @Test("Local and remote endpoint aliases")
    func endpointAliases() {
        // Test that LocalEndpoint and RemoteEndpoint are just aliases
        let local = LocalEndpoint(kind: .host("localhost"))
        let remote = RemoteEndpoint(kind: .host("example.com"))
        
        // Both should be Endpoint types
        let _: Endpoint = local
        let _: Endpoint = remote
        
        // Should be able to use them interchangeably
        var endpoints: [Endpoint] = []
        endpoints.append(local)
        endpoints.append(remote)
        
        #expect(endpoints.count == 2)
    }
    
    @Test("Endpoint with service name")
    func endpointWithService() {
        var endpoint = Endpoint(kind: .host("example.com"))
        endpoint.service = "https"
        
        #expect(endpoint.service == "https")
        #expect(endpoint.description == "example.com(https)")
        
        // With both port and service (port takes precedence)
        endpoint.port = 8443
        #expect(endpoint.description == "example.com:8443")
    }
    
    @Test("Endpoint equality")
    func endpointEquality() {
        let endpoint1 = Endpoint(kind: .host("example.com"))
        var endpoint2 = Endpoint(kind: .host("example.com"))
        endpoint2.port = 443
        
        // Same host, different ports
        #expect(endpoint1 != endpoint2)
        
        // Make them equal
        var endpoint3 = Endpoint(kind: .host("example.com"))
        endpoint3.port = 443
        #expect(endpoint2 == endpoint3)
        
        // Different hosts
        let endpoint4 = Endpoint(kind: .host("other.com"))
        #expect(endpoint1 != endpoint4)
    }
}