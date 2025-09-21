// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftAtproto",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(
            name: "SwiftAtproto",
            targets: ["SwiftAtproto"]
        ),
        .library(name: "ATProtoMacro",
                 targets: ["ATProtoMacro"]),
        .executable(
            name: "swift-atproto",
            targets: ["swift-atproto"]
        ),
        .plugin(
            name: "SwiftAtprotoPlugin",
            targets: ["Generate Source Code"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-libp2p/swift-cid", exact: "0.0.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "601.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.3.1"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.55.5"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.19.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
    ],
    targets: [
        .target(
            name: "SwiftAtproto",
            dependencies: [
                .product(name: "CID", package: "swift-cid"),
                .product(name: "AsyncHTTPClient", package: "async-http-client", condition: .when(platforms: [.linux])),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "SwiftAtprotoLex",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "SourceControl"
        ),
        .executableTarget(
            name: "swift-atproto",
            dependencies: [
                "SwiftAtprotoLex",
                .target(name: "SourceControl", condition: .when(platforms: [.macOS])),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CommandLineTool"
        ),
        .macro(
            name: "Macros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "ATProtoMacro", dependencies: ["Macros", "SwiftAtproto"]),
        .testTarget(
            name: "SwiftAtprotoTests",
            dependencies: ["SwiftAtproto"]
        ),
        .testTarget(
            name: "MacrosTests",
            dependencies: [
                "Macros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .plugin(name: "Generate Source Code",
                capability: .command(
                    intent: .custom(verb: "swift-atproto", description: "Formats Swift source files using SwiftFormat"),
                    permissions: [
                        .writeToPackageDirectory(reason: "This command reformats source files"),
                        .allowNetworkConnections(scope: .all(ports: [443]), reason: "fetch lexicons"),
                    ]
                ),
                dependencies: [.target(name: "swift-atproto")],
                path: "Plugins/SwiftAtprotoPlugin"),
    ]
)
