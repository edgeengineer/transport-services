// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This package supports cross-platform Bluetooth using:
// - Linux: BluetoothLinux (conditionally imported)
// - Darwin: CoreBluetooth (system framework)

let package = Package(
    name: "TransportServices",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "TransportServices",
            targets: ["TransportServices"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.83.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
        .package(url: "https://github.com/PureSwift/Bluetooth.git", branch: "master"),
        .package(url: "https://github.com/PureSwift/GATT.git", branch: "master"),
        // Linux-specific Bluetooth implementation
        .package(url: "https://github.com/PureSwift/BluetoothLinux.git", branch: "master")
    ],
    targets: [
        .target(
            name: "TransportServices",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Bluetooth", package: "Bluetooth"),
                .product(name: "GATT", package: "GATT"),
                .product(name: "BluetoothLinux", package: "BluetoothLinux", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TransportServicesTests",
            dependencies: ["TransportServices"]
        ),
        // Example executables
        .executableTarget(
            name: "SimpleClient",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["SimpleClient.swift"]
        ),
        .executableTarget(
            name: "MulticastExample",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["MulticastExample.swift"]
        ),
        .executableTarget(
            name: "RendezvousExample",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["RendezvousExample.swift"]
        ),
        .executableTarget(
            name: "ConnectionGroupExample",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["ConnectionGroupExample.swift"]
        ),
        .executableTarget(
            name: "SecurityCallbackExample",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["SecurityCallbackExample.swift"]
        ),
        .executableTarget(
            name: "ZeroRTTExample",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["ZeroRTTExample.swift"]
        ),
        .executableTarget(
            name: "BluetoothExample",
            dependencies: ["TransportServices"],
            path: "Examples",
            sources: ["BluetoothExample.swift"]
        ),
    ]
)