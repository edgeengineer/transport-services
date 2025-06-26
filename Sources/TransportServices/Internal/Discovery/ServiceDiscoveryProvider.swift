#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Internal protocol for discovery/advertising backends
///
/// Implementations of this protocol provide the actual discovery
/// and advertising functionality for specific transport types
/// (e.g., mDNS, BLE)
protocol ServiceDiscoveryProvider: Sendable {
    /// The name of this provider (for debugging)
    var name: String { get }
    
    /// Discovers services matching the given configuration
    ///
    /// - Parameter service: The service to discover
    /// - Returns: An async stream of discovered instances
    func discover(service: DiscoverableService) -> AsyncStream<DiscoveredInstance>
    
    /// Advertises a service for the given listener
    ///
    /// - Parameters:
    ///   - service: The service to advertise
    ///   - listener: The listener to advertise for
    /// - Returns: An advertisement handle for lifecycle management
    func advertise(
        service: DiscoverableService,
        for listener: Listener
    ) async throws -> Advertisement
    
    /// Checks if this provider can handle the given service type
    ///
    /// - Parameter service: The service to check
    /// - Returns: True if this provider can handle the service
    func canHandle(service: DiscoverableService) -> Bool
}