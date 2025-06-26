#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Advertising extensions for Listener
extension Listener {
    /// Advertises this listener as a discoverable service
    ///
    /// This method makes the listener discoverable via the appropriate
    /// transport mechanisms (mDNS/Bonjour for IP listeners, BLE advertising
    /// for BLE listeners).
    ///
    /// The advertisement will continue until explicitly stopped or until
    /// the listener is closed.
    ///
    /// Example usage:
    /// ```swift
    /// // Create and start a listener
    /// let listener = try await Listener(
    ///     localEndpoint: .any(port: 8080),
    ///     parameters: .tcp
    /// )
    ///
    /// // Advertise it as an HTTP service
    /// let service = DiscoverableService.mdns(
    ///     serviceType: "_http._tcp",
    ///     metadata: ["path": "/api/v1"]
    /// )
    /// let advertisement = try await listener.advertise(service)
    ///
    /// // Later, stop advertising
    /// await advertisement.stop()
    /// ```
    ///
    /// - Parameter service: The service configuration to advertise
    /// - Returns: An Advertisement handle for managing the advertisement lifecycle
    /// - Throws: If the service cannot be advertised on this listener's transport
    public func advertise(
        _ service: DiscoverableService
    ) async throws -> Advertisement {
        try await DiscoveryManager.shared.advertise(
            service: service,
            for: self
        )
    }
}