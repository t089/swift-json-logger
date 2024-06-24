// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-json-logger",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "JSONLogger",
            targets: ["JSONLogger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/tayloraswift/swift-json.git", from: "1.1.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "JSONLogger",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "JSON", package: "swift-json")
            ]),
        .testTarget(
            name: "JSONLoggerTests",
            dependencies: [
                "JSONLogger",
                .product(name: "JSON", package: "swift-json")
                ]),
    ]
)
