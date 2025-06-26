# Generic Discovery & Advertising Plan

This document outlines a phased plan to introduce generic service discovery and advertising capabilities into the `transport-services` library. The goal is to create a unified, high-level API that allows applications to broadcast their availability and find other services, regardless of the underlying transport mechanism (e.g., IP-based mDNS/Bonjour or Bluetooth LE).

This extension builds directly on the core TAPS philosophy: an application should declare its *intent*, and the framework should manage the implementation details.

---

## Core Concepts: A Unified API

The new API will be centered around two main actions: **discovering** services and **advertising** a local listener.

-   **`Discovery`**: An application will be able to ask the framework to find all instances of a particular service type (e.g., `_my-app._tcp`). The framework will return a stream of results, where each result contains the necessary `Endpoint` information to connect, regardless of whether it was found via mDNS or BLE scan.

-   **`Advertising`**: An application with an active `Listener` can make it discoverable on the local network. The framework will handle the specific protocol broadcasts (mDNS, BLE advertising packets) needed to make it visible to others.

---

## Phase 1: API Design & Abstraction Layer

This foundational phase focuses on creating the public-facing API and the internal protocols that will allow for multiple, interchangeable discovery backends.

### 1. Define Public API Models

Create the data structures that will be used by the application developer.

-   **`DiscoverableService`**: A struct to configure what to advertise or discover.
    ```swift
    public struct DiscoverableService {
        /// The service type, e.g., "_http._tcp" for mDNS or a CBUUID for BLE.
        public let type: String
        
        /// The discovery domain, e.g., "local." for mDNS. Optional for other transports.
        public let domain: String?
        
        /// Key-value metadata to broadcast (maps to TXT records or advertising data).
        public let metadata: [String: String]
    }
    ```

-   **`DiscoveredInstance`**: A struct representing a single discovered service instance. This is the result of a discovery operation.
    ```swift
    public struct DiscoveredInstance {
        /// The human-readable name of the instance (e.g., "Alice's MacBook Pro").
        public let name: String
        
        /// A list of one or more resolved endpoints that can be used to connect.
        /// This array could contain both IP and BLE endpoints for a dual-stack device.
        public let endpoints: [RemoteEndpoint]
        
        /// The metadata broadcast by the service.
        public let metadata: [String: String]
    }
    ```

-   **`Advertisement`**: An actor or class returned when advertising begins, used to manage its lifecycle.
    ```swift
    public actor Advertisement {
        /// Stops broadcasting the service advertisement.
        public func stop() async { ... }
    }
    ```

### 2. Define Public API Actions

-   **For Discovery**: A static, top-level function that returns an `AsyncStream` of results.
    ```swift
    // In a new file, e.g., TransportServices+Discovery.swift
    extension TransportServices {
        public static func discover(
            _ service: DiscoverableService
        ) -> AsyncStream<DiscoveredInstance> { ... }
    }
    ```

-   **For Advertising**: An extension method on the `Listener` object.
    ```swift
    // In a new file, e.g., Listener+Advertising.swift
    extension Listener {
        public func advertise(
            _ service: DiscoverableService
        ) async throws -> Advertisement { ... }
    }
    ```

### 3. Create the Internal Abstraction Layer

-   **`ServiceDiscoveryProvider` Protocol**: An internal protocol that all discovery/advertising backends will implement.
    ```swift
    internal protocol ServiceDiscoveryProvider {
        func discover(service: DiscoverableService) -> AsyncStream<DiscoveredInstance>
        func advertise(service: DiscoverableService, for listener: Listener) async throws -> Advertisement
    }
    ```
-   **`DiscoveryManager`**: An internal manager that holds a list of all available providers (e.g., `mDNSProvider`, `BLEProvider`). When a discovery is requested, it will start discovery on all providers and merge their `AsyncStream` results into one single stream that is returned to the user.

---

## Phase 2: IP-Based Discovery (mDNS / Bonjour)

This phase implements the backend for service discovery on local IP networks.

**Actions:**
1.  **Create `mDNSProvider`**: An internal class that conforms to `ServiceDiscoveryProvider`.
2.  **Apple Platforms Implementation**:
    -   Use `Network.framework` for both discovery and advertising. It provides a modern, robust implementation of Bonjour.
    -   **Discovery**: Use `NWBrowser` to browse for Bonjour services of the specified type. As services are found and resolved, convert the results into our generic `DiscoveredInstance` struct, populating the `endpoints` array with IP-based `RemoteEndpoint`s.
    -   **Advertising**: Use the `service` property of the `NWListener` (which underlies our TAPS `Listener`) to register and publish the service via Bonjour.
3.  **Linux Implementation**:
    -   Integrate a library that can communicate with the system's **Avahi daemon** over D-Bus. This is the standard way to implement mDNS on Linux.
    -   The implementation will need to map Avahi's signals and method calls to the `ServiceDiscoveryProvider` protocol requirements.

---

## Phase 3: BLE-Based Discovery and Advertising

This phase implements the backend for BLE, building on the work from the `BLUETOOTH_EXPANSION.md` plan.

**Actions:**
1.  **Create `BLEProvider`**: A new internal class that conforms to `ServiceDiscoveryProvider`.
2.  **Implementation via PureSwift/Bluetooth**:
    -   **Discovery**: Use the `hostController.central.scan()` method from the PureSwift library. Configure the scan to filter for peripherals that are advertising the `CBUUID` specified in `DiscoverableService.type`. When a peripheral is found, parse its advertising data to create the `DiscoveredInstance`, populating its `endpoints` array with a BLE-based `RemoteEndpoint`.
    -   **Advertising**: Use the `hostController.peripheral.startAdvertising()` method. The `DiscoverableService` properties will be encoded into the advertising packet: the `type` becomes the `serviceUUID`, and the `metadata` is placed in the `serviceData` field. The advertisement points to the L2CAP PSM that the backing `Listener` is using.

---

## Phase 4: Documentation and Examples

Update user-facing documentation to showcase these powerful new features.

**Actions:**
1.  **Create `DISCOVERY_API_GUIDE.md`**: A new document explaining the concepts of generic discovery and how to use the new APIs.
2.  **Add New Examples**:
    -   **Local Chat App**: A command-line or GUI app where users can find each other on the local network via mDNS and initiate a `Connection`.
    -   **IoT Control App**: An app that discovers nearby BLE-based smart devices and connects to them, showing how the same discovery API works for a completely different transport.
    -   **Dual-Protocol Service**: A server example that creates a single `Listener` and advertises it over *both* mDNS and BLE simultaneously. A client example would then discover this one service and be able to connect via either Wi-Fi or BLE, letting the TAPS framework race them and pick the best path automatically. 