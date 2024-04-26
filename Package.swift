// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAtproto",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(
            name: "SwiftAtproto",
            targets: ["SwiftAtproto"]
        ),
        .executable(
            name: "swift-atproto",
            targets: ["LexGen"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "510.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.3.1"),

    ],
    targets: [
        .target(
            name: "SwiftAtproto"
        ),
        .target(
            name: "SwiftAtprotoLex",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "LexGen",
            dependencies: [
                "SwiftAtprotoLex",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CommandLineTool"
        ),
        .testTarget(
            name: "SwiftAtprotoTests",
            dependencies: ["SwiftAtproto"]
        ),
    ]
)
