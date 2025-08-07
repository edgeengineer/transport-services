// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransportServices",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TransportServices",
            targets: ["TransportServices"]
        ),
        .executable(
            name: "SimpleServer",
            targets: ["SimpleServer"]
        ),
        .executable(
            name: "SimpleClient",
            targets: ["SimpleClient"]
        ),
    ],
    targets: [
        .target(
            name: "TransportServices"
        ),
        .executableTarget(
            name: "SimpleServer",
            dependencies: ["TransportServices"],
            path: "Examples",
            exclude: ["WindowsTest.swift", "SimpleClient.swift"],
            sources: ["SimpleServer.swift"]
        ),
        .executableTarget(
            name: "SimpleClient",
            dependencies: ["TransportServices"],
            path: "Examples",
            exclude: ["WindowsTest.swift", "SimpleServer.swift"],
            sources: ["SimpleClient.swift"]
        ),
        .testTarget(
            name: "TransportServicesTests",
            dependencies: ["TransportServices"]
        ),
    ]
)
