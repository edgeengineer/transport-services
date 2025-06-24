#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Dynamic security callbacks for trust verification and identity challenges.
///
/// These callbacks enable applications to make real-time trust and identity
/// decisions during the security handshake, as specified in RFC 9622 §6.3.8.
public struct SecurityCallbacks: Sendable {
    
    // MARK: - Types
    
    /// Result of trust verification
    public enum TrustVerificationResult: Sendable {
        /// Accept the peer's certificate chain
        case accept
        
        /// Reject the peer's certificate chain
        case reject
        
        /// Accept with specific conditions
        case acceptWithConditions(conditions: [String])
    }
    
    /// Information about a certificate in the chain
    public struct CertificateInfo: Sendable {
        /// The certificate data in DER format
        public let certificateData: Data
        
        /// Subject name
        public let subject: String
        
        /// Issuer name
        public let issuer: String
        
        /// Serial number
        public let serialNumber: String
        
        /// Not valid before date
        public let notBefore: Date
        
        /// Not valid after date
        public let notAfter: Date
        
        /// Subject alternative names
        public let subjectAlternativeNames: [String]
        
        /// Whether this is a CA certificate
        public let isCA: Bool
        
        /// Key usage flags
        public let keyUsage: Set<String>
        
        public init(certificateData: Data,
                    subject: String,
                    issuer: String,
                    serialNumber: String,
                    notBefore: Date,
                    notAfter: Date,
                    subjectAlternativeNames: [String] = [],
                    isCA: Bool = false,
                    keyUsage: Set<String> = []) {
            self.certificateData = certificateData
            self.subject = subject
            self.issuer = issuer
            self.serialNumber = serialNumber
            self.notBefore = notBefore
            self.notAfter = notAfter
            self.subjectAlternativeNames = subjectAlternativeNames
            self.isCA = isCA
            self.keyUsage = keyUsage
        }
    }
    
    /// Context for trust verification
    public struct TrustVerificationContext: Sendable {
        /// The peer's certificate chain
        public let certificateChain: [CertificateInfo]
        
        /// The hostname being connected to (if available)
        public let serverName: String?
        
        /// The protocol being used (e.g., "TLS 1.3")
        public let protocolVersion: String
        
        /// Cipher suite being negotiated
        public let cipherSuite: String?
        
        /// Whether OCSP stapling is available
        public let ocspResponse: Data?
        
        /// Whether SCT (Certificate Transparency) is available
        public let sctList: [Data]?
        
        public init(certificateChain: [CertificateInfo],
                    serverName: String? = nil,
                    protocolVersion: String,
                    cipherSuite: String? = nil,
                    ocspResponse: Data? = nil,
                    sctList: [Data]? = nil) {
            self.certificateChain = certificateChain
            self.serverName = serverName
            self.protocolVersion = protocolVersion
            self.cipherSuite = cipherSuite
            self.ocspResponse = ocspResponse
            self.sctList = sctList
        }
    }
    
    /// Context for identity challenges
    public struct IdentityChallengeContext: Sendable {
        /// The type of authentication requested
        public let authType: String
        
        /// Acceptable certificate authorities (if any)
        public let acceptableIssuers: [String]
        
        /// The server name being connected to
        public let serverName: String?
        
        /// Available client identities
        public let availableIdentities: [(certificate: Data, privateKey: Data)]
        
        public init(authType: String,
                    acceptableIssuers: [String] = [],
                    serverName: String? = nil,
                    availableIdentities: [(certificate: Data, privateKey: Data)] = []) {
            self.authType = authType
            self.acceptableIssuers = acceptableIssuers
            self.serverName = serverName
            self.availableIdentities = availableIdentities
        }
    }
    
    /// Result of identity challenge
    public struct IdentityChallengeResult: Sendable {
        /// The selected certificate data
        public let certificate: Data
        
        /// The private key data (or reference)
        public let privateKey: Data
        
        /// Optional password for encrypted keys
        public let password: String?
        
        public init(certificate: Data, privateKey: Data, password: String? = nil) {
            self.certificate = certificate
            self.privateKey = privateKey
            self.password = password
        }
    }
    
    // MARK: - Callbacks
    
    /// Callback invoked to verify a peer's certificate chain.
    ///
    /// This callback is invoked during the security handshake when the peer
    /// presents its certificate chain. The application can inspect the chain
    /// and decide whether to accept or reject it.
    ///
    /// - Warning: This callback blocks the handshake and must return quickly.
    ///   Long-running operations should be avoided.
    public var trustVerificationCallback: (@Sendable (TrustVerificationContext) async -> TrustVerificationResult)?
    
    /// Callback invoked when a private key operation is required for authentication.
    ///
    /// This callback is invoked when the server requests client authentication
    /// and a private key operation is needed. The application can select which
    /// identity to use or provide credentials dynamically.
    ///
    /// - Warning: This callback blocks the handshake and must return quickly.
    public var identityChallengeCallback: (@Sendable (IdentityChallengeContext) async -> IdentityChallengeResult?)?
    
    /// Callback invoked when a pre-shared key is needed.
    ///
    /// This callback is invoked during PSK negotiation to provide the key
    /// material for a given identity.
    public var pskCallback: (@Sendable (Data) async -> Data?)?
    
    /// Callback invoked for session ticket storage.
    ///
    /// This allows applications to store session tickets for resumption.
    public var sessionTicketCallback: (@Sendable (Data) async -> Void)?
    
    // MARK: - Initialization
    
    public init() {}
}

