//
//  PlatformListener.swift
//  
//
//  Maximilian Alexander
//

#if !hasFeature(Embedded)
#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
#endif

/// Platform-specific listener implementation
public protocol PlatformListener: Sendable {
    /// Start listening for incoming connections
    func listen() async throws
    
    /// Stop listening
    func stop() async
    
    /// Accept an incoming connection
    func accept() async throws -> any PlatformConnection
}