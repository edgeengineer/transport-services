#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct SecurityParameters: Sendable {
    public var allowedProtocols : [String] = []      // "TLS1_3", "QUIC‑TLS" …
    public var serverCertificates: [Data] = []       // DER blobs, PKCS#12, etc.
    public var clientCertificates: [Data] = []
    public var pinnedServerCerts : [Data] = []
    public var alpn             : [String] = []      // ["h2", "hq‑29"]
    public var preSharedKey     : (identity:Data,key:Data)?
    
    /// Server private keys corresponding to serverCertificates
    /// - If empty, assumes serverCertificates contains PKCS#12 data with embedded keys
    /// - If provided, must have same count as serverCertificates
    public var serverPrivateKeys: [Data] = []
    
    /// Password for encrypted private keys or PKCS#12 files
    public var privateKeyPassword: String?
    
    /// Dynamic security callbacks for trust verification and identity challenges
    public var callbacks: SecurityCallbacks = SecurityCallbacks()
    
    public init() {}
    
    /// Creates SecurityParameters with callbacks
    public init(callbacks: SecurityCallbacks) {
        self.init()
        self.callbacks = callbacks
    }
}