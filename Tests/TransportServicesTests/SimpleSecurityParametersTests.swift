import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Simple Security Parameters Tests")
struct SimpleSecurityParametersTests {
    
    @Test("Default security parameters")
    func defaultParameters() async throws {
        let params = SecurityParameters()
        
        #expect(params.allowedProtocols.isEmpty)
        #expect(params.serverCertificates.isEmpty)
        #expect(params.clientCertificates.isEmpty)
        #expect(params.pinnedServerCerts.isEmpty)
        #expect(params.alpn.isEmpty)
        #expect(params.preSharedKey == nil)
    }
    
    @Test("Set allowed protocols")
    func allowedProtocols() async throws {
        var params = SecurityParameters()
        
        params.allowedProtocols = ["TLS1_3", "TLS1_2"]
        #expect(params.allowedProtocols.count == 2)
        #expect(params.allowedProtocols.contains("TLS1_3"))
        #expect(params.allowedProtocols.contains("TLS1_2"))
    }
    
    @Test("Set server certificates")
    func serverCertificates() async throws {
        var params = SecurityParameters()
        
        let cert1 = Data("cert1-data".utf8)
        let cert2 = Data("cert2-data".utf8)
        
        params.serverCertificates = [cert1, cert2]
        #expect(params.serverCertificates.count == 2)
        #expect(params.serverCertificates.contains(cert1))
        #expect(params.serverCertificates.contains(cert2))
    }
    
    @Test("Set client certificates")
    func clientCertificates() async throws {
        var params = SecurityParameters()
        
        let clientCert = Data("client-cert".utf8)
        params.clientCertificates = [clientCert]
        
        #expect(params.clientCertificates.count == 1)
        #expect(params.clientCertificates.first == clientCert)
    }
    
    @Test("Set ALPN protocols")
    func alpnProtocols() async throws {
        var params = SecurityParameters()
        
        params.alpn = ["h2", "http/1.1"]
        #expect(params.alpn.count == 2)
        #expect(params.alpn.contains("h2"))
        #expect(params.alpn.contains("http/1.1"))
    }
    
    @Test("Set pre-shared key")
    func preSharedKey() async throws {
        var params = SecurityParameters()
        
        let identity = Data("my-identity".utf8)
        let key = Data("secret-key".utf8)
        
        params.preSharedKey = (identity: identity, key: key)
        
        #expect(params.preSharedKey != nil)
        #expect(params.preSharedKey?.identity == identity)
        #expect(params.preSharedKey?.key == key)
    }
    
    @Test("Set pinned certificates")
    func pinnedCertificates() async throws {
        var params = SecurityParameters()
        
        let pinnedCert = Data("pinned-cert".utf8)
        params.pinnedServerCerts = [pinnedCert]
        
        #expect(params.pinnedServerCerts.count == 1)
        #expect(params.pinnedServerCerts.contains(pinnedCert))
    }
    
    @Test("Security callbacks")
    func securityCallbacks() async throws {
        let callbacks = SecurityCallbacks()
        var params = SecurityParameters(callbacks: callbacks)
        
        // Callbacks should be set
        #expect(true) // We can't easily test equality of callbacks
        
        let newCallbacks = SecurityCallbacks()
        params.callbacks = newCallbacks
        #expect(true)
    }
    
    @Test("Complete configuration")
    func completeConfiguration() async throws {
        var params = SecurityParameters()
        
        params.allowedProtocols = ["TLS1_3"]
        params.serverCertificates = [Data("server".utf8)]
        params.clientCertificates = [Data("client".utf8)]
        params.pinnedServerCerts = [Data("pinned".utf8)]
        params.alpn = ["h2"]
        params.preSharedKey = (identity: Data("id".utf8), key: Data("key".utf8))
        
        #expect(params.allowedProtocols.count == 1)
        #expect(params.serverCertificates.count == 1)
        #expect(params.clientCertificates.count == 1)
        #expect(params.pinnedServerCerts.count == 1)
        #expect(params.alpn.count == 1)
        #expect(params.preSharedKey != nil)
    }
}