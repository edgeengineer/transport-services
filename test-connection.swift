#!/usr/bin/env swift

import Foundation
import TransportServices

print("Starting connection test...")

// Create endpoint
var endpoint = RemoteEndpoint()
endpoint.ipAddress = "1.1.1.1"
endpoint.port = 80

print("Creating preconnection...")
let preconnection = Preconnection(
    remoteEndpoints: [endpoint]
)

print("Initiating connection...")

Task {
    do {
        let connection = try await preconnection.initiate()
        print("Connection established! State: \(await connection.state)")
        
        await connection.close()
        print("Connection closed")
        
        exit(0)
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

// Keep the program running
RunLoop.main.run()