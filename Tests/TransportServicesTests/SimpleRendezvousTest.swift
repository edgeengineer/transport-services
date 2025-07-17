import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Simple Rendezvous Test", .disabled("Temporarily disabled pending rendezvous implementation fixes"))
struct SimpleRendezvousTest {
    
    @Test("Simple connection test")
    func simpleConnection() async throws {
        // This test verifies basic connectivity without rendezvous
        let port = try await TestUtils.getAvailablePort()
        
        // Create server
        var serverLocal = LocalEndpoint(kind: .host("127.0.0.1"))
        serverLocal.port = port
        
        let serverPreconnection = Preconnection(
            local: [serverLocal],
            transport: TransportProperties()
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
        
        let clientPreconnection = Preconnection(
            remote: [clientRemote],
            transport: TransportProperties()
        )
        
        let clientConnection = try await clientPreconnection.initiate()
        let serverConnection = try await serverTask.value
        
        // Verify states
        let clientState = await clientConnection.state
        let serverState = await serverConnection.state
        
        #expect(clientState == .established)
        #expect(serverState == .established)
        
        // Test sending
        let testMsg = Message(Data("Hello".utf8))
        try await clientConnection.send(testMsg)
        
        let received = try await serverConnection.receive()
        let text = String(data: received.data, encoding: .utf8) ?? ""
        #expect(text == "Hello")
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
}