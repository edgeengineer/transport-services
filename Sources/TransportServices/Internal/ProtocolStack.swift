#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@preconcurrency import NIOCore

/// Internal protocol that defines the interface for different transport protocol stacks.
///
/// This protocol allows the Transport Services implementation to work with
/// different underlying transport technologies (TCP/IP, Bluetooth, etc.) in a uniform way.
protocol ProtocolStack: Sendable {
    /// The type of endpoint this stack can handle
    associatedtype EndpointType: Sendable
    
    /// Initiates a connection to a remote endpoint
    /// - Parameters:
    ///   - remote: The remote endpoint to connect to
    ///   - local: Optional local endpoint to bind to
    ///   - properties: Transport properties for the connection
    ///   - eventLoop: The event loop to use for async operations
    /// - Returns: A future that completes when the connection is established
    func connect(
        to remote: EndpointType,
        from local: EndpointType?,
        with properties: TransportProperties,
        on eventLoop: EventLoop
    ) async throws -> Channel
    
    /// Starts listening for incoming connections
    /// - Parameters:
    ///   - local: The local endpoint to listen on
    ///   - properties: Transport properties for the listener
    ///   - eventLoop: The event loop to use for async operations
    /// - Returns: A channel representing the listening socket
    func listen(
        on local: EndpointType,
        with properties: TransportProperties,
        on eventLoop: EventLoop
    ) async throws -> Channel
    
    /// Checks if this stack can handle the given endpoint
    /// - Parameter endpoint: The endpoint to check
    /// - Returns: true if this stack can handle the endpoint
    static func canHandle(endpoint: Endpoint) -> Bool
    
    /// Gets the priority of this stack for the given properties
    /// - Parameter properties: The transport properties
    /// - Returns: A priority value (higher is better)
    static func priority(for properties: TransportProperties) -> Int
}