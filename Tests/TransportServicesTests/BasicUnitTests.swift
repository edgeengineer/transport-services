import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Basic Unit Tests")
struct BasicUnitTests {
    
    @Test("Preference enum values")
    func preferenceEnum() {
        #expect(Preference.noPreference.rawValue == 2)
        #expect(Preference.prohibit.rawValue == 0)
        #expect(Preference.require.rawValue == 4)
    }
    
    @Test("Endpoint creation and modification")
    func endpointCreation() {
        var endpoint = Endpoint(kind: .host("example.com"))
        endpoint.port = 443
        #expect(endpoint.port == 443)
    }
    
    @Test("Transport properties default values")
    func transportPropertiesDefaults() {
        let properties = TransportProperties()
        #expect(properties.reliability == .require)
        #expect(properties.preserveOrder == .require)
        #expect(properties.multipathMode == .disabled)
    }
    
    @Test("Message context default values")
    func messageContextDefaults() {
        let context = MessageContext()
        #expect(context.priority == 100)
        #expect(context.safelyReplayable == false)
        #expect(context.final == false)
    }
    
    @Test("Message creation with data")
    func messageCreation() {
        let data = Data("Hello".utf8)
        let message = Message(data)
        #expect(message.data == data)
        #expect(message.context.priority == 100)
    }
}