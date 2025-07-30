// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransportServices",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TransportServices",
            targets: ["TransportServices"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "TransportServices",
            dependencies: [
                .target(name: "CIOUring", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "CIOUring",
            dependencies: ["liburing"]
        ),
        .systemLibrary(
            name: "liburing",
            pkgConfig: "liburing",
            providers: [
                .apt(["liburing-dev"]),
                .brew(["liburing"])
            ]
        ),
        .testTarget(
            name: "TransportServicesTests",
            dependencies: ["TransportServices"]
        ),
    ]
)
