// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransportServices",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v11),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TransportServices",
            targets: ["TransportServices"]
        ),
    ],
    targets: [
        .target(
            name: "TransportServices"
        ),
        .testTarget(
            name: "TransportServicesTests",
            dependencies: ["TransportServices"]
        ),
    ]
)
