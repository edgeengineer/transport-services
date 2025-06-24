import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Test func preferenceEnum() {
    #expect(Preference.noPreference.rawValue == 2)
    #expect(Preference.prohibit.rawValue == 0)
    #expect(Preference.require.rawValue == 4)
}

@Test func endpointCreation() {
    var endpoint = Endpoint(kind: .host("example.com"))
    endpoint.port = 443
    #expect(endpoint.port == 443)
}

@Test func transportPropertiesDefaults() {
    let properties = TransportProperties()
    #expect(properties.reliability == .require)
    #expect(properties.preserveOrder == .require)
    #expect(properties.multipathMode == .disabled)
}

@Test func messageContextDefaults() {
    let context = MessageContext()
    #expect(context.priority == 100)
    #expect(context.safelyReplayable == false)
    #expect(context.final == false)
}

@Test func messageCreation() {
    let data = Data("Hello".utf8)
    let message = Message(data)
    #expect(message.data == data)
    #expect(message.context.priority == 100)
}