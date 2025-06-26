# Bluetooth (Non-IP) Expansion Plan

This document outlines a phased plan to extend the `transport-services` library to support non-IP-based communication systems, using Bluetooth Low Energy (BLE) with L2CAP as the primary example. This work demonstrates the true power of the TAPS architecture by creating a single, unified API for developers to handle vastly different underlying network transports.

The guiding principle is that an application developer should be able to express their *intent* (e.g., "I need a reliable channel to a device offering this service") and the framework should handle the implementation details, whether that's over TCP/IP or a BLE L2CAP channel.

---

## Phase 1: Abstracting the API for Transport Agnosticism ✅ COMPLETED

This phase focuses on decoupling the public API from IP-specific concepts. The goal is to allow `Endpoint`s and `TransportProperties` to describe resources and requirements beyond the world of hosts, ports, and IP addresses.

**Status:** Completed on June 25, 2025
- ✅ Extended `Endpoint.Kind` enum to support BLE cases
- ✅ Added convenience initializers for BLE endpoints
- ✅ Added `preferLowPower` property to `TransportProperties`
- ✅ Updated all internal switch statements to handle new endpoint types
- ✅ All tests passing

### 1. Generalize the `Endpoint` Model

The `Endpoint` is the most critical piece to abstract. It must be able to represent not just an IP address and port, but also a BLE peripheral, a specific service, or other non-IP addresses.

**Actions:**
-   Modify the internal structure of `Endpoint` to support different address types. For example:
    ```swift
    // Internal Representation
    internal enum EndpointType {
        case ip(host: String, port: UInt16)
        case ble(peripheralUUID: UUID, psm: L2CAPPSM)
        case bleService(serviceUUID: CBUUID, psm: L2CAPPSM?)
    }
    ```
-   Introduce new public initializers for `RemoteEndpoint` and `LocalEndpoint` that are specific to BLE. This makes the API clear and type-safe.
    ```swift
    // New Public Initializers
    extension RemoteEndpoint {
        /// Creates an endpoint representing a specific BLE peripheral.
        public init(blePeripheral: CBPeripheral, psm: L2CAPPSM) { ... }

        /// Creates an endpoint representing any peripheral advertising a specific service.
        public init(bleService: CBUUID, psm: L2CAPPSM? = nil) { ... }
    }

    extension LocalEndpoint {
        /// Creates a local endpoint for listening by publishing an L2CAP channel.
        public init(blePublishedPSM: L2CAPPSM) { ... }
    }
    ```
-   The existing `init(host:port:)` initializer will create an `.ip` endpoint internally.

### 2. Introduce Transport-Specific `TransportProperties`

While most TAPS properties map well, we can introduce new ones that allow the framework's selection logic to intelligently prefer certain transports.

**Actions:**
-   Add new `TransportProperties` that can guide selection between IP and non-IP transports.
    ```swift
    public struct TransportProperties {
        // ... existing properties
        
        /// A preference for using low-power transports when available.
        /// Setting this to .require would prevent Wi-Fi from being chosen
        /// if a BLE path was viable.
        public var preferLowPower: Preference = .noPreference
    }
    ```

## Phase 2: Implementing the BLE Protocol Stack via PureSwift/Bluetooth 🚧 IN PROGRESS

This phase involves building the new transport backend by integrating the [PureSwift/Bluetooth library (v7.2.2)](https://github.com/PureSwift/Bluetooth), a cross-platform solution for Swift. This approach avoids writing separate platform-specific code for CoreBluetooth (Apple) and BlueZ (Linux) and accelerates the implementation.

**Status:** Foundation work completed on June 25, 2025
- ✅ Added PureSwift/Bluetooth dependency to Package.swift
- ✅ Created `ProtocolStack` protocol for transport abstraction
- ✅ Implemented `IPStack` wrapping existing SwiftNIO functionality
- ✅ Created `BLEStack` with proper error handling for unimplemented L2CAP
- ✅ Created `TransportStackManager` for protocol selection
- ✅ Documented BLE L2CAP architecture in BLEChannel.swift
- ✅ All code compiles cleanly with no warnings
- ✅ All tests pass (60/60)
- ✅ Added conditional platform dependencies:
  - BluetoothLinux 5.0.5+ (Linux only)
  - GATT 3.3.1+ (all platforms)
- ✅ Implemented platform-specific L2CAP code paths:
  - Linux: Uses BluetoothLinux.L2CAPSocket
  - Darwin: Placeholder for CoreBluetooth CBL2CAPChannel
- ✅ Channel wrapper implementation completed:
  - BLEChannel implements NIO Channel and ChannelCore protocols
  - BLEServerChannel for accepting BLE connections
  - Mock implementation ready for platform-specific L2CAP integration

**Actions:**
-   **Add Dependencies:** Update `Package.swift` to include `PureSwift/Bluetooth` and its necessary platform-specific backends.
    ```swift
    // In Package.swift
    .package(url: "https://github.com/PureSwift/Bluetooth.git", branch: "master"),

    ```
-   **Create `BLEStack` Wrapper:** This internal class will conform to our `ProtocolStack` protocol. Instead of managing native platform APIs, it will hold a `BluetoothHostController` and interact with the high-level `Central` and `Peripheral` objects from the PureSwift library.
-   **Map TAPS Actions to PureSwift/Bluetooth APIs:**
    -   `preconnection.initiate()`: Will use `hostController.central` to `scan()` for peripherals. On discovery, it will `connect()` and then use the `peripheral.l2cap.connect(psm:)` method to establish the L2CAP channel. The resulting `L2CAPSocket` will be used for I/O.
    -   `preconnection.listen()`: Will use `hostController.peripheral` to configure a GATT server and listen for incoming L2CAP connection requests on the specified PSM.
    -   `connection.send(message)`: Will write the message data to the `L2CAPSocket` stream provided by PureSwift.
    -   **Event Handling:** Map events from the PureSwift library to TAPS events:
        -   Successful `l2cap.connect` -> Triggers a `.ready` event.
        -   Data received on the `L2CAPSocket` stream -> Triggers a `.received(message)` event.
        -   Disconnection notifications -> Triggers a `.closed` or `.error` event.

## Phase 3: Integration, Racing, and Selection

This is where the two worlds are united. The core `TransportServices` implementation will be taught how to manage, select, and race IP and BLE candidates.

**Actions:**
-   **Update Candidate Gathering:** The `gatherCandidates()` logic will be enhanced. When an application calls `initiate()`, the framework will look at the `Preconnection`:
    1.  If the `Endpoint` is explicitly BLE (e.g., `init(bleService:)`), it will only create `BLEStack` candidates.
    2.  If the `Endpoint` is IP-based, it will only create `IPStack` candidates.
    3.  **If the `Endpoint` and `TransportProperties` are abstract enough to be satisfied by both** (e.g., an app requires reliability and provides a generic service identifier that could be resolved via DNS-SD over IP and via BLE advertisement), the framework will generate candidates for **both** stacks.
-   **Enable Cross-Transport Racing:** The existing candidate racing logic will now seamlessly handle a list containing both `IPStack` and `BLEStack` candidates. The first candidate to successfully establish a channel and fire a `.ready` event becomes the active `Connection`. The application receives this `Connection` and can use it without ever knowing which transport was chosen.

## Phase 4: Documentation & Examples

To make this powerful new capability usable, documentation and examples are essential.

**Actions:**
-   **Update `API_GUIDE.md`:** Create a new section detailing how to work with non-IP transports, explaining the new `Endpoint` initializers and transport properties.
-   **Create New Examples:**
    -   **IoT Client:** An example of an app that connects to a smart device. The app simply requests a reliable connection to the device's service, and the library automatically chooses between Wi-Fi and BLE based on proximity and network conditions.
    -   **BLE Peripheral:** An example of using `Listener` to create an accessory that provides a service over an L2CAP channel.
    -   **Data Transfer:** An example showing that the `send()` and `receive()` code is identical for both an IP-based connection and a BLE-based connection. 