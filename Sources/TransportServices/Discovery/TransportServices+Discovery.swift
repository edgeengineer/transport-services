#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Service discovery functionality for Transport Services
///
/// The Discovery enum provides a namespace for service discovery
/// operations that work across different transport types.
public enum Discovery {
    /// Discovers services matching the given configuration
    ///
    /// This method searches for services across all available transports
    /// (IP via mDNS/Bonjour, Bluetooth, etc.) and returns a stream of discovered
    /// instances.
    ///
    /// Example usage:
    /// ```swift
    /// // Discover HTTP services via mDNS
    /// let httpService = DiscoverableService.mdns(serviceType: "_http._tcp")
    /// for await instance in Discovery.discover(httpService) {
    ///     print("Found: \(instance.name) at \(instance.endpoints)")
    /// }
    ///
    /// // Discover Bluetooth services
    /// let bleService = DiscoverableService.ble(serviceUUID: myServiceUUID)
    /// for await instance in Discovery.discover(bleService) {
    ///     print("Found Bluetooth device: \(instance.name)")
    /// }
    /// ```
    ///
    /// - Parameter service: The service configuration to discover
    /// - Returns: An async stream of discovered service instances
    public static func discover(
        _ service: DiscoverableService
    ) -> AsyncStream<DiscoveredInstance> {
        DiscoveryManager.shared.discover(service: service)
    }
    
    /// Discovers services with a timeout
    ///
    /// This convenience method discovers services for a limited time period
    /// and returns all discovered instances.
    ///
    /// - Parameters:
    ///   - service: The service configuration to discover
    ///   - timeout: The maximum time to wait for discoveries
    /// - Returns: An array of discovered instances
    public static func discover(
        _ service: DiscoverableService,
        timeout: TimeInterval
    ) async -> [DiscoveredInstance] {
        await withTaskGroup(of: DiscoveredInstance?.self) { group in
            var instances: [DiscoveredInstance] = []
            
            // Start discovery task
            group.addTask {
                for await instance in discover(service) {
                    return instance
                }
                return nil
            }
            
            // Start timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            
            // Collect results until timeout
            for await instance in group {
                if let instance = instance {
                    instances.append(instance)
                }
            }
            
            return instances
        }
    }
}