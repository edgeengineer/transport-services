import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("0-RTT Tests")
struct ZeroRTTTests {
    
    @Test("InitiateWithSend for 0-RTT data")
    func initiateWithSend() async throws {
        // Create server
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        var serverProperties = TransportProperties()
        serverProperties.zeroRTT = .prefer
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: serverProperties
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client with 0-RTT
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var clientProperties = TransportProperties()
        clientProperties.zeroRTT = .prefer
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: clientProperties
        )
        
        // Send data with connection establishment
        var earlyContext = MessageContext()
        earlyContext.safelyReplayable = true  // Required for 0-RTT
        let earlyData = Message(Data("0-RTT Hello".utf8), context: earlyContext)
        let clientConnection = try await clientPreconnection.initiateWithSend(earlyData)
        
        // Server should receive the early data
        let serverConnection = try await serverTask.value
        let received = try await serverConnection.receive()
        let text = String(data: received.data, encoding: .utf8) ?? ""
        
        #expect(text == "0-RTT Hello")
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
    
    @Test("0-RTT rejection handling")
    func zeroRTTRejection() async throws {
        // Create server that doesn't support 0-RTT
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        var serverProperties = TransportProperties()
        serverProperties.zeroRTT = .prohibit
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: serverProperties
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client requesting 0-RTT
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var clientProperties = TransportProperties()
        clientProperties.zeroRTT = .require
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: clientProperties
        )
        
        // This should either fail or fall back to regular connection
        do {
            let earlyData = Message(Data("0-RTT Required".utf8))
            let clientConnection = try await clientPreconnection.initiateWithSend(earlyData)
            
            // If connection succeeded, it means fallback worked
            let serverConnection = try await serverTask.value
            
            // Data should still be received (but not as 0-RTT)
            let received = try await serverConnection.receive()
            let text = String(data: received.data, encoding: .utf8) ?? ""
            #expect(text == "0-RTT Required")
            
            // Cleanup
            await clientConnection.close()
            await serverConnection.close()
        } catch {
            // If 0-RTT was required and rejected, connection should fail
            #expect(error is TransportError)
        }
        
        await listener.stop()
    }
    
    @Test("Safely replayable message flag")
    func safelyReplayableMessage() async throws {
        let port = try await TestUtils.getAvailablePort()
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        var serverProperties = TransportProperties()
        serverProperties.zeroRTT = .prefer
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: serverProperties
        )
        
        let listener = try await serverPreconnection.listen()
        
        // Accept connection task
        let serverTask = Task {
            for try await connection in listener.newConnections {
                return connection
            }
            throw TransportError.establishmentFailure("No connections received")
        }
        
        // Create client
        var clientRemote = RemoteEndpoint(kind: .host("127.0.0.1"))
        clientRemote.port = port
        
        var clientProperties = TransportProperties()
        clientProperties.zeroRTT = .prefer
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: clientProperties
        )
        
        // Create message marked as safely replayable
        var messageContext = MessageContext()
        messageContext.safelyReplayable = true
        let earlyData = Message(Data("Idempotent request".utf8), context: messageContext)
        
        let clientConnection = try await clientPreconnection.initiateWithSend(earlyData)
        let serverConnection = try await serverTask.value
        
        let received = try await serverConnection.receive()
        let text = String(data: received.data, encoding: .utf8) ?? ""
        
        #expect(text == "Idempotent request")
        #expect(received.context.safelyReplayable == true)
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
}