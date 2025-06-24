import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import TransportServices

@Suite("Simple Transport Properties Tests")
struct SimpleTransportPropertiesTests {
    
    @Test("Default transport properties values")
    func defaultValues() async throws {
        let properties = TransportProperties()
        
        #expect(properties.reliability == .require)
        #expect(properties.preserveOrder == .require)
        #expect(properties.congestionControl == .require)
        #expect(properties.direction == .bidirectional)
    }
    
    @Test("Set reliability preferences")
    func reliabilityPreferences() async throws {
        var properties = TransportProperties()
        
        properties.reliability = .prohibit
        #expect(properties.reliability == .prohibit)
        
        properties.reliability = .avoid
        #expect(properties.reliability == .avoid)
        
        properties.reliability = .prefer
        #expect(properties.reliability == .prefer)
        
        properties.reliability = .require
        #expect(properties.reliability == .require)
    }
    
    @Test("Set multipath modes")
    func multipathModes() async throws {
        var properties = TransportProperties()
        
        properties.multipathMode = .disabled
        #expect(properties.multipathMode == .disabled)
        
        properties.multipathMode = .active
        #expect(properties.multipathMode == .active)
        
        properties.multipathMode = .passive
        #expect(properties.multipathMode == .passive)
    }
    
    @Test("Set direction")
    func connectionDirection() async throws {
        var properties = TransportProperties()
        
        properties.direction = .sendOnly
        #expect(properties.direction == .sendOnly)
        
        properties.direction = .recvOnly
        #expect(properties.direction == .recvOnly)
        
        properties.direction = .bidirectional
        #expect(properties.direction == .bidirectional)
    }
    
    @Test("Interface preferences")
    func interfacePreferences() async throws {
        var properties = TransportProperties()
        
        properties.interfacePreferences["en0"] = .prefer
        properties.interfacePreferences["pdp_ip0"] = .avoid
        
        #expect(properties.interfacePreferences["en0"] == .prefer)
        #expect(properties.interfacePreferences["pdp_ip0"] == .avoid)
    }
    
    @Test("Convenience property creators")
    func convenienceCreators() async throws {
        let reliable = TransportProperties.reliableStream()
        #expect(reliable.reliability == .require)
        
        let message = TransportProperties.reliableMessage()
        #expect(message.preserveMsgBoundaries == .require)
        
        let datagram = TransportProperties.unreliableDatagram()
        #expect(datagram.reliability == .prohibit)
        
        let lowLatency = TransportProperties.lowLatency()
        #expect(lowLatency.zeroRTT == .prefer)
        
        let bulk = TransportProperties.bulkData()
        #expect(bulk.reliability == .require)
        
        let media = TransportProperties.mediaStream()
        #expect(media.reliability == .avoid)
        
        let privacy = TransportProperties.privacyEnhanced()
        #expect(privacy.useTemporaryAddress == .require)
    }
    
    @Test("Property modification")
    func propertyModification() async throws {
        var properties = TransportProperties()
        
        // Modify multiple properties
        properties.reliability = .prefer
        properties.preserveOrder = .avoid
        properties.congestionControl = .prohibit
        properties.disableNagle = true
        
        // Verify all changes
        #expect(properties.reliability == .prefer)
        #expect(properties.preserveOrder == .avoid)
        #expect(properties.congestionControl == .prohibit)
        #expect(properties.disableNagle == true)
    }
    
    @Test("Data integrity properties")
    func dataIntegrityProperties() async throws {
        var properties = TransportProperties()
        
        properties.fullChecksumSend = .require
        #expect(properties.fullChecksumSend == .require)
        
        properties.fullChecksumRecv = .prefer
        #expect(properties.fullChecksumRecv == .prefer)
    }
}