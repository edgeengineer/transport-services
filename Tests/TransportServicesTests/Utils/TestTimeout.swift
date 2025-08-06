//
//  TestTimeout.swift
//  
//
//  Test utility for handling timeouts in async tests
//

import Foundation
@testable import TransportServices

/// Error thrown when a test operation times out
struct TestTimeoutError: Error, CustomStringConvertible {
    let operation: String
    let timeout: Duration
    
    var description: String {
        "Operation '\(operation)' timed out after \(timeout)"
    }
}

/// Executes an async operation with a timeout
/// - Parameters:
///   - timeout: The duration to wait before timing out
///   - operation: A description of the operation for error messages
///   - body: The async closure to execute
/// - Returns: The result of the operation
/// - Throws: TestTimeoutError if the operation doesn't complete within the timeout
func withTimeout<T: Sendable>(
    _ timeout: Duration = .seconds(5),
    operation: String = "operation",
    body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation task
        group.addTask {
            try await body()
        }
        
        // Add timeout task
        group.addTask {
            let effectiveTimeout: Duration = timeout
            try await Task.sleep(for: effectiveTimeout)
            throw TestTimeoutError(operation: operation, timeout: effectiveTimeout)
        }
        
        // Return the first result (either success or timeout)
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// Waits for a condition to become true within a timeout period
/// - Parameters:
///   - timeout: The duration to wait before timing out
///   - pollInterval: How often to check the condition
///   - operation: A description of the operation for error messages
///   - condition: The condition to check
/// - Throws: TestTimeoutError if the condition doesn't become true within the timeout
func waitForCondition(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(20),
    operation: String = "condition",
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let effectiveTimeout: Duration = timeout
    let deadline = ContinuousClock.now + effectiveTimeout
    
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    
    throw TestTimeoutError(operation: operation, timeout: effectiveTimeout)
}

/// Waits for a non-nil result within a timeout period
/// - Parameters:
///   - timeout: The duration to wait before timing out
///   - pollInterval: How often to check for the result
///   - operation: A description of the operation for error messages
///   - producer: The closure that produces the optional result
/// - Returns: The non-nil result
/// - Throws: TestTimeoutError if no result is produced within the timeout
func waitForResult<T: Sendable>(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(20),
    operation: String = "result",
    producer: @escaping @Sendable () async -> T?
) async throws -> T {
    let effectiveTimeout: Duration = timeout
    let deadline = ContinuousClock.now + effectiveTimeout
    
    while ContinuousClock.now < deadline {
        if let result = await producer() {
            return result
        }
        try await Task.sleep(for: pollInterval)
    }
    
    throw TestTimeoutError(operation: operation, timeout: effectiveTimeout)
}

/// Extension for testing connection states with timeout
extension Connection {
    /// Waits for the connection to reach a specific state
    /// - Parameters:
    ///   - targetState: The state to wait for
    ///   - timeout: How long to wait before timing out
    /// - Throws: TestTimeoutError if the state isn't reached within the timeout
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
    /// - Throws: TestTimeoutError if no connection is accepted within the timeout
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