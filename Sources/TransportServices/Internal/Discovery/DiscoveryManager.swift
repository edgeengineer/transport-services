#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Internal manager for coordinating discovery providers
///
/// This singleton manages all available discovery providers and
/// coordinates discovery/advertising operations across them
final class DiscoveryManager: @unchecked Sendable {
    /// Shared singleton instance
    static let shared = DiscoveryManager()
    
    /// Available discovery providers
    private var providers: [ServiceDiscoveryProvider] = []
    
    /// Lock for thread-safe provider access
    private let providersLock = NSLock()
    
    private init() {
        // Initialize with default providers
        setupDefaultProviders()
    }
    
    /// Sets up the default discovery providers
    private func setupDefaultProviders() {
        // TODO: Add mDNS provider when implemented
        
        // Register Bluetooth provider
        let bluetoothProvider = BluetoothDiscoveryProvider()
        register(provider: bluetoothProvider)
    }
    
    /// Registers a discovery provider
    ///
    /// - Parameter provider: The provider to register
    func register(provider: ServiceDiscoveryProvider) {
        providersLock.lock()
        defer { providersLock.unlock() }
        
        providers.append(provider)
    }
    
    /// Discovers services across all capable providers
    ///
    /// - Parameter service: The service to discover
    /// - Returns: A merged stream of results from all providers
    func discover(service: DiscoverableService) -> AsyncStream<DiscoveredInstance> {
        let capableProviders = providers.filter { $0.canHandle(service: service) }
        
        guard !capableProviders.isEmpty else {
            // Return empty stream if no providers can handle this service
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        
        // If only one provider, return its stream directly
        if capableProviders.count == 1 {
            return capableProviders[0].discover(service: service)
        }
        
        // Merge multiple streams
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for provider in capableProviders {
                        group.addTask {
                            for await instance in provider.discover(service: service) {
                                continuation.yield(instance)
                            }
                        }
                    }
                    
                    // Wait for all providers to complete
                    await group.waitForAll()
                    continuation.finish()
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Advertises a service using all capable providers
    ///
    /// - Parameters:
    ///   - service: The service to advertise
    ///   - listener: The listener to advertise for
    /// - Returns: A composite advertisement managing all provider advertisements
    func advertise(
        service: DiscoverableService,
        for listener: Listener
    ) async throws -> Advertisement {
        let capableProviders = providers.filter { $0.canHandle(service: service) }
        
        guard !capableProviders.isEmpty else {
            throw Advertisement.AdvertisementError.unsupportedTransport
        }
        
        // Create composite advertisement
        let compositeAd = Advertisement(service: service, listener: listener)
        
        // Start advertising on all capable providers
        var providerAds: [Advertisement] = []
        var errors: [Error] = []
        
        await withTaskGroup(of: Result<Advertisement, Error>.self) { group in
            for provider in capableProviders {
                group.addTask {
                    do {
                        let ad = try await provider.advertise(
                            service: service,
                            for: listener
                        )
                        return .success(ad)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            
            for await result in group {
                switch result {
                case .success(let ad):
                    providerAds.append(ad)
                case .failure(let error):
                    errors.append(error)
                }
            }
        }
        
        // If all providers failed, throw the first error
        if providerAds.isEmpty && !errors.isEmpty {
            throw errors[0]
        }
        
        // Add stop handler to stop all provider advertisements
        await compositeAd.addStopHandler {
            await withTaskGroup(of: Void.self) { group in
                for ad in providerAds {
                    group.addTask {
                        await ad.stop()
                    }
                }
            }
        }
        
        return compositeAd
    }
}