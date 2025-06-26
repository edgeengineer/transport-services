#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A handle for managing a service advertisement
///
/// This actor represents an active service advertisement and provides
/// methods to control its lifecycle. When an advertisement is stopped
/// or deallocated, the service will no longer be discoverable.
public actor Advertisement {
    /// The service being advertised
    public let service: DiscoverableService
    
    /// The listener associated with this advertisement
    public let listener: Listener
    
    /// Internal state tracking
    private var isActive: Bool = true
    
    /// Callbacks to execute when stopping
    private var stopHandlers: [() async -> Void] = []
    
    /// Creates a new advertisement
    ///
    /// - Parameters:
    ///   - service: The service to advertise
    ///   - listener: The listener to advertise for
    internal init(service: DiscoverableService, listener: Listener) {
        self.service = service
        self.listener = listener
    }
    
    /// Adds a stop handler to be called when the advertisement is stopped
    ///
    /// - Parameter handler: The async handler to execute on stop
    internal func addStopHandler(_ handler: @escaping () async -> Void) {
        stopHandlers.append(handler)
    }
    
    /// Stops broadcasting the service advertisement
    ///
    /// After calling this method, the service will no longer be
    /// discoverable by other devices.
    public func stop() async {
        guard isActive else { return }
        isActive = false
        
        // Execute all stop handlers
        for handler in stopHandlers {
            await handler()
        }
        stopHandlers.removeAll()
    }
    
    /// Returns whether the advertisement is currently active
    public var isAdvertising: Bool {
        isActive
    }
    
    deinit {
        // Note: We can't call async stop() from deinit
        // Users should explicitly call stop() to ensure proper cleanup
        // The discovery providers should handle cleanup on their end
    }
}

// MARK: - Advertisement State

extension Advertisement {
    /// Errors that can occur during advertising
    public enum AdvertisementError: Error, CustomStringConvertible {
        case alreadyStopped
        case listenerClosed
        case unsupportedTransport
        case invalidConfiguration
        case systemError(String)
        
        public var description: String {
            switch self {
            case .alreadyStopped:
                return "Advertisement has already been stopped"
            case .listenerClosed:
                return "Associated listener has been closed"
            case .unsupportedTransport:
                return "Service type not supported by any available transport"
            case .invalidConfiguration:
                return "Invalid configuration for advertisement"
            case .systemError(let message):
                return "System error: \(message)"
            }
        }
    }
}