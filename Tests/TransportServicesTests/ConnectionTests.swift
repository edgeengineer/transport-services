import Testing
import NIO
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Connection Tests")
struct ConnectionTests {
    
    @Test("Basic client-server connection")
    func basicConnection() async throws {
        let (client, server, listener) = try await TestUtils.createClientServerPair()
        
        // Verify connections are established
        let clientState = await client.state
        let serverState = await server.state
        #expect(clientState == .established)
        #expect(serverState == .established)
        
        // Cleanup
        await client.close()
        await server.close()
        await listener.stop()
    }
    
    @Test("Send and receive messages") 
    func sendReceiveMessages() async throws {
        let (clientConnection, serverConnection, listener) = try await TestUtils.createClientServerPair()
        
        // Send message from client to server
        let testData = Data("Hello, Server!".utf8)
        let message = Message(testData)
        try await clientConnection.send(message)
        
        // Receive on server
        let received = try await serverConnection.receive()
        #expect(received.data == testData)
        
        // Send response from server to client
        let responseData = Data("Hello, Client!".utf8)
        let responseMessage = Message(responseData)
        try await serverConnection.send(responseMessage)
        
        // Receive on client
        let clientReceived = try await clientConnection.receive()
        #expect(clientReceived.data == responseData)
        
        // Cleanup
        await clientConnection.close()
        await serverConnection.close()
        await listener.stop()
    }
}