#!/usr/bin/env swift

import TransportServices
import Foundation

/// Security Callback Example
///
/// This example demonstrates:
/// - Custom certificate validation
/// - Client certificate selection
/// - Trust verification with conditions
/// - Security policy implementation

@main
struct SecurityCallbackExample {
    static func main() async {
        do {
            // Example 1: Custom trust verification
            await customTrustVerification()
            
            // Example 2: Client certificate authentication
            await clientCertificateAuth()
            
        } catch {
            print("Error: \(error)")
        }
    }
    
    // MARK: - Custom Trust Verification
    
    static func customTrustVerification() async {
        do {
            print("\n=== Custom Trust Verification Example ===")
            
            var endpoint = RemoteEndpoint(kind: .host("self-signed.example.com"))
            endpoint.port = 443
            
            // Create security parameters with custom trust callback
            var security = SecurityParameters()
            
            // Set up trust verification callback
            security.callbacks.trustVerificationCallback = { context in
                print("Trust verification callback invoked")
                print("Server: \(context.serverName ?? "unknown")")
                print("Protocol: \(context.protocolVersion)")
                print("Certificates in chain: \(context.certificateChain.count)")
                
                // Custom validation logic
                for (index, cert) in context.certificateChain.enumerated() {
                    print("Certificate \(index):")
                    print("  Subject: \(cert.subject)")
                    print("  Issuer: \(cert.issuer)")
                    print("  Valid from: \(cert.notBefore) to \(cert.notAfter)")
                    
                    // Check for self-signed certificate
                    if cert.subject == cert.issuer {
                        print("  ⚠️  Self-signed certificate detected")
                        
                        // In production, verify against pinned certificate
                        if isPinnedCertificate(cert) {
                            print("  ✅ Certificate matches pinned certificate")
                            return .accept
                        }
                    }
                }
                
                // Accept with conditions for demo
                return .acceptWithConditions(conditions: [
                    "Certificate is self-signed",
                    "Accepted for demo purposes only"
                ])
            }
            
            let preconnection = Preconnection(
                remote: [endpoint],
                transport: .reliableStream(),
                security: security
            )
            
            print("Connecting with custom trust verification...")
            let connection = try await preconnection.initiate()
            
            print("Connected successfully with custom trust!")
            await connection.close()
            
        } catch {
            print("Custom trust error: \(error)")
        }
    }
    
    // MARK: - Client Certificate Authentication
    
    static func clientCertificateAuth() async {
        do {
            print("\n=== Client Certificate Authentication Example ===")
            
            var endpoint = RemoteEndpoint(kind: .host("mtls.example.com"))
            endpoint.port = 443
            
            var security = SecurityParameters()
            
            // Set up client certificate callback
            security.callbacks.identityChallengeCallback = { context in
                print("Identity challenge callback invoked")
                print("Auth type: \(context.authType)")
                print("Server name: \(context.serverName ?? "unknown")")
                print("Acceptable issuers: \(context.acceptableIssuers)")
                
                // Load client certificate and key
                guard let (certificate, privateKey) = loadClientCredentials() else {
                    print("No client certificate available")
                    return nil
                }
                
                return SecurityCallbacks.IdentityChallengeResult(
                    certificate: certificate,
                    privateKey: privateKey,
                    password: nil  // Key not encrypted
                )
            }
            
            let preconnection = Preconnection(
                remote: [endpoint],
                transport: .reliableStream(),
                security: security
            )
            
            print("Connecting with client certificate...")
            let connection = try await preconnection.initiate()
            
            print("Mutual TLS authentication successful!")
            await connection.close()
            
        } catch {
            print("Client cert error: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
    static func isPinnedCertificate(_ cert: SecurityCallbacks.CertificateInfo) -> Bool {
        // In real app, compare against stored certificate hash
        let pinnedHash = "expected_certificate_hash"
        let certHash = cert.certificateData.base64EncodedString() // Simplified
        return certHash == pinnedHash
    }
    
    static func loadClientCredentials() -> (certificate: Data, privateKey: Data)? {
        // In real app, load from keychain or secure storage
        print("Loading client certificate from secure storage...")
        
        // Demo data (would be actual certificate/key data)
        let dummyCert = Data("-----BEGIN CERTIFICATE-----".utf8)
        let dummyKey = Data("-----BEGIN PRIVATE KEY-----".utf8)
        
        return (dummyCert, dummyKey)
    }
}

// Production Security Policy Example:
/*
class SecurityPolicy {
    private let pinnedCertificates: Set<Data>
    private let allowSelfSigned: Bool
    private let minimumTLSVersion: String
    
    init(pinnedCertificates: Set<Data> = [],
         allowSelfSigned: Bool = false,
         minimumTLSVersion: String = "TLS 1.3") {
        self.pinnedCertificates = pinnedCertificates
        self.allowSelfSigned = allowSelfSigned
        self.minimumTLSVersion = minimumTLSVersion
    }
    
    func createSecurityParameters() -> SecurityParameters {
        var params = SecurityParameters()
        
        // Configure allowed protocols
        params.allowedProtocols = ["TLS 1.3", "TLS 1.2"]
        
        // Set up trust verification
        params.callbacks.trustVerificationCallback = { [self] context in
            // Check TLS version
            guard context.protocolVersion >= self.minimumTLSVersion else {
                return .reject
            }
            
            // Certificate pinning
            if !self.pinnedCertificates.isEmpty {
                let leafCert = context.certificateChain.first
                if let cert = leafCert,
                   self.pinnedCertificates.contains(cert.certificateData) {
                    return .accept
                }
                return .reject
            }
            
            // Self-signed handling
            if let cert = context.certificateChain.first,
               cert.subject == cert.issuer {
                return self.allowSelfSigned ? .accept : .reject
            }
            
            // Default to system validation
            return .accept
        }
        
        return params
    }
}

// Usage:
let policy = SecurityPolicy(
    pinnedCertificates: loadPinnedCertificates(),
    allowSelfSigned: false
)

let preconnection = Preconnection(
    remote: [endpoint],
    security: policy.createSecurityParameters()
)
*/