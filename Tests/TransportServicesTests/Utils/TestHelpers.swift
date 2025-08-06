//
//  TestHelpers.swift
//  
//
//  Test helper functions that work with Timeout.swift from Swift NIO
//

import Foundation
@testable import TransportServices

/// Waits for a condition to become true within a timeout period
/// - Parameters:
///   - timeout: The duration to wait before timing out
///   - pollInterval: How often to check the condition
///   - operation: A description of the operation for error messages
///   - condition: The condition to check
/// - Throws: TimeOutError if the condition doesn't become true within the timeout
func waitForCondition(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(20),
    operation: String = "condition",
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    
    struct ConditionTimeoutError: Error {
        let operation: String
        let timeout: Duration
    }
    
    throw ConditionTimeoutError(operation: operation, timeout: timeout)
}

/// Extension for testing connection states with timeout
extension Connection {
    /// Waits for the connection to reach a specific state
    /// - Parameters:
    ///   - targetState: The state to wait for
    ///   - timeout: How long to wait before timing out
    /// - Throws: TimeOutError if the state isn't reached within the timeout
    func waitForState(
        _ targetState: ConnectionState,
        timeout: Duration = .seconds(5)
    ) async throws {
        try await waitForCondition(
            timeout: timeout,
            operation: "waiting for connection state \(targetState)"
        ) { [weak self] in
            guard let self else { return false }
            return await self.state == targetState
        }
    }
}

/// Extension for testing listener with timeout
extension Listener {
    /// Waits for a connection to be accepted
    /// - Parameters:
    ///   - timeout: How long to wait for a connection
    /// - Returns: The number of accepted connections
    /// - Throws: TimeOutError if no connection is accepted within the timeout
    func waitForConnection(
        timeout: Duration = .seconds(5)
    ) async throws -> UInt {
        let initialCount = await self.getAcceptedConnectionCount()
        
        try await waitForCondition(
            timeout: timeout,
            operation: "waiting for connection acceptance"
        ) { [weak self] in
            guard let self else { return false }
            return await self.getAcceptedConnectionCount() > initialCount
        }
        
        return await self.getAcceptedConnectionCount()
    }
}