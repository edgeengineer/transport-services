#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore
@preconcurrency import NIOSSL
import Crypto

/// Integrates security callbacks with NIO SSL.
///
/// This handler bridges between Transport Services security callbacks
/// and NIO SSL's verification mechanisms.
final class SecurityCallbackHandler: @unchecked Sendable {
    
    private let callbacks: SecurityCallbacks
    private let serverName: String?
    
    init(callbacks: SecurityCallbacks, serverName: String?) {
        self.callbacks = callbacks
        self.serverName = serverName
    }
    
    /// Creates a custom verification callback for NIO SSL
    func makeNIOSSLCustomVerificationCallback() -> NIOSSLCustomVerificationCallback {
        // TODO: Implement proper async callback bridge when NIO SSL supports it
        // For now, return a simple callback that accepts all certificates
        return { certificates, promise in
            // Note: This is a simplified implementation
            // Proper implementation would verify certificates using the callbacks
            promise.succeed(.certificateVerified)
        }
    }
    
    /// Performs trust verification using the callback
    private func performTrustVerification(
        certificates: [NIOSSLCertificate],
        callbacks: SecurityCallbacks,
        serverName: String?
    ) async -> NIOSSLVerificationResult {
        
        guard let trustCallback = callbacks.trustVerificationCallback else {
            // No callback provided, use default verification
            return .certificateVerified
        }
        
        // Convert NIO certificates to our CertificateInfo format
        let certInfos = certificates.compactMap { cert -> SecurityCallbacks.CertificateInfo? in
            guard let x509 = try? cert.toDERBytes() else { return nil }
            
            // Parse certificate details (simplified for now)
            return SecurityCallbacks.CertificateInfo(
                certificateData: Data(x509),
                subject: extractSubject(from: cert),
                issuer: extractIssuer(from: cert),
                serialNumber: extractSerialNumber(from: cert),
                notBefore: Date(),
                notAfter: Date(),
                subjectAlternativeNames: extractSANs(from: cert),
                isCA: false,
                keyUsage: []
            )
        }
        
        let context = SecurityCallbacks.TrustVerificationContext(
            certificateChain: certInfos,
            serverName: serverName,
            protocolVersion: "TLS 1.3", // Would need to get actual version
            cipherSuite: nil,
            ocspResponse: nil,
            sctList: nil
        )
        
        let result = await trustCallback(context)
        
        switch result {
        case .accept:
            return .certificateVerified
        case .reject:
            return .failed
        case .acceptWithConditions(let conditions):
            // Log conditions but accept for now
            print("Certificate accepted with conditions: \(conditions)")
            return .certificateVerified
        }
    }
    
    // MARK: - Certificate Parsing Helpers
    
    private func extractSubject(from cert: NIOSSLCertificate) -> String {
        // Simplified - would need proper X.509 parsing
        return "CN=Unknown"
    }
    
    private func extractIssuer(from cert: NIOSSLCertificate) -> String {
        // Simplified - would need proper X.509 parsing
        return "CN=Unknown Issuer"
    }
    
    private func extractSerialNumber(from cert: NIOSSLCertificate) -> String {
        // Simplified - would need proper X.509 parsing
        return "0000"
    }
    
    private func extractSANs(from cert: NIOSSLCertificate) -> [String] {
        // Simplified - would need proper X.509 parsing
        return []
    }
}

/// Extension to handle client certificate selection
extension SecurityCallbackHandler {
    
    /// Creates a callback for client certificate selection
    func makeClientCertificateCallback() -> (@Sendable ([String]) async throws -> (NIOSSLCertificate, NIOSSLPrivateKey)?) {
        return { acceptableIssuers in
            guard let identityCallback = self.callbacks.identityChallengeCallback else {
                return nil
            }
            
            let context = SecurityCallbacks.IdentityChallengeContext(
                authType: "TLS Client Certificate",
                acceptableIssuers: acceptableIssuers,
                serverName: self.serverName,
                availableIdentities: []
            )
            
            guard let result = await identityCallback(context) else {
                return nil
            }
            
            do {
                // Convert the result to NIO SSL types
                let cert = try NIOSSLCertificate(bytes: Array(result.certificate), format: .der)
                let key = try NIOSSLPrivateKey(bytes: Array(result.privateKey), format: .der)
                return (cert, key)
            } catch {
                print("Failed to create certificate/key: \(error)")
                return nil
            }
        }
    }
}