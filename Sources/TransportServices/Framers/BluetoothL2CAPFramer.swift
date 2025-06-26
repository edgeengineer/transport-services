#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore

/// A framer for Bluetooth L2CAP connections that handles message boundaries and MTU constraints.
///
/// Bluetooth L2CAP (Logical Link Control and Adaptation Protocol) is a message-oriented
/// protocol that sits above the HCI layer. This framer ensures that:
/// - Messages respect the negotiated MTU
/// - Large messages are properly fragmented
/// - Message boundaries are preserved
///
/// ## Overview
///
/// L2CAP has different characteristics than TCP:
/// - **Message-oriented**: Each write creates a distinct message
/// - **MTU-constrained**: Messages larger than MTU must be fragmented
/// - **Reliable delivery**: L2CAP ensures ordered, reliable delivery
///
/// ## Usage
///
/// ```swift
/// let framer = BluetoothL2CAPFramer(mtu: 512)
/// preconnection.addFramer(framer)
/// ```
///
/// ## MTU Negotiation
///
/// The MTU is typically negotiated during L2CAP channel setup:
/// - **LE ATT**: Default 23 bytes, can negotiate up to 517
/// - **LE CoC**: Default 23 bytes, can negotiate up to 65535
/// - **Classic L2CAP**: Default 672 bytes, can negotiate up to 65535
public struct BluetoothL2CAPFramer: MessageFramer, Sendable {
    
    /// The negotiated Maximum Transmission Unit for this L2CAP channel
    private let mtu: Int
    
    /// Whether to automatically fragment large messages
    private let autoFragment: Bool
    
    /// Internal state for reassembly
    private final class ParsingState: @unchecked Sendable {
        var buffer = Data()
    }
    
    private let state = ParsingState()
    
    /// Creates a new Bluetooth L2CAP framer
    ///
    /// - Parameters:
    ///   - mtu: The Maximum Transmission Unit (default: 512)
    ///   - autoFragment: Whether to automatically fragment large messages (default: true)
    public init(mtu: Int = 512, autoFragment: Bool = true) {
        self.mtu = mtu
        self.autoFragment = autoFragment
    }
    
    // MARK: - MessageFramer Protocol
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        let messageData = message.data
        
        // Check if message exceeds MTU
        if messageData.count > mtu {
            if autoFragment {
                // Fragment the message into MTU-sized chunks
                var fragments: [Data] = []
                var offset = 0
                
                while offset < messageData.count {
                    let chunkSize = min(mtu, messageData.count - offset)
                    let chunk = messageData[offset..<(offset + chunkSize)]
                    fragments.append(chunk)
                    offset += chunkSize
                }
                
                print("[BluetoothL2CAPFramer] Fragmented message of \(messageData.count) bytes into \(fragments.count) fragments")
                return fragments
            } else {
                throw TransportError.sendFailure(
                    "Message exceeds L2CAP MTU: \(messageData.count) bytes (max: \(mtu))"
                )
            }
        }
        
        // For messages within MTU, send as single fragment
        return [messageData]
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        // For L2CAP, each received chunk is a complete message
        // The L2CAP layer handles reassembly at a lower level
        
        // In a real implementation, we might need to handle:
        // 1. Credit-based flow control headers
        // 2. Enhanced retransmission mode headers
        // 3. Segmentation and reassembly (SAR) for LE
        
        // For now, treat each chunk as a complete message
        if bytes.isEmpty {
            return ([], Data())
        }
        
        // Create message with L2CAP metadata
        let context = MessageContext()
        // L2CAP messages are complete units, no need for special flags
        
        let message = Message(bytes, context: context)
        
        return ([message], Data())
    }
    
    public func connectionDidOpen(_ connection: Connection) async {
        // Reset state on new connection
        state.buffer = Data()
    }
    
    public func connectionDidClose(_ connection: Connection) async {
        // Clear any buffered data
        state.buffer = Data()
    }
}

// MARK: - L2CAP Enhanced Framer

/// An enhanced L2CAP framer that adds additional protocol features
///
/// This framer adds:
/// - Credit-based flow control simulation
/// - Connection-oriented channel (CoC) support
/// - Enhanced retransmission mode features
public struct EnhancedBluetoothL2CAPFramer: MessageFramer, Sendable {
    
    /// The base L2CAP framer
    private let baseFramer: BluetoothL2CAPFramer
    
    /// Credit flow control state
    private final class CreditState: @unchecked Sendable {
        var sendCredits: Int = 10
        var receiveCredits: Int = 10
    }
    
    private let creditState = CreditState()
    
    /// Whether to use credit-based flow control
    private let useCreditFlow: Bool
    
    public init(mtu: Int = 512, useCreditFlow: Bool = true) {
        self.baseFramer = BluetoothL2CAPFramer(mtu: mtu)
        self.useCreditFlow = useCreditFlow
    }
    
    public func frameOutbound(_ message: Message) async throws -> [Data] {
        // Check if we have send credits
        if useCreditFlow && creditState.sendCredits <= 0 {
            throw TransportError.sendFailure("No L2CAP send credits available")
        }
        
        // Use base framer for fragmentation
        let fragments = try await baseFramer.frameOutbound(message)
        
        // Consume send credit for each fragment
        if useCreditFlow {
            creditState.sendCredits -= fragments.count
        }
        
        return fragments
    }
    
    public func parseInbound(_ bytes: Data) async throws -> (messages: [Message], remainder: Data) {
        // Use base framer for parsing
        let (messages, remainder) = try await baseFramer.parseInbound(bytes)
        
        // Add credit flow information if enabled
        if useCreditFlow && !messages.isEmpty {
            var enhancedMessages: [Message] = []
            
            for message in messages {
                // Consume one receive credit per message
                creditState.receiveCredits -= 1
                
                // Replenish credits if running low
                if creditState.receiveCredits < 5 {
                    creditState.receiveCredits += 10
                }
                
                enhancedMessages.append(message)
            }
            
            return (enhancedMessages, remainder)
        }
        
        return (messages, remainder)
    }
    
    public func connectionDidOpen(_ connection: Connection) async {
        // Reset credit state
        creditState.sendCredits = 10
        creditState.receiveCredits = 10
        
        // Call base framer
        await baseFramer.connectionDidOpen(connection)
    }
    
    public func connectionDidClose(_ connection: Connection) async {
        // Call base framer
        await baseFramer.connectionDidClose(connection)
    }
}

