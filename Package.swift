// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "SwiftAtproto",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(
      name: "SwiftAtproto",
      targets: ["SwiftAtproto"]
    ),
    .library(
      name: "ATProtoCrypto",
      targets: ["ATProtoCrypto"]),
    .library(
      name: "ATProtoMacro",
      targets: ["ATProtoMacro"]),
    .executable(
      name: "swift-atproto",
      targets: ["swift-atproto"]
    ),
    .plugin(
      name: "ATProtoLexiconFetcher",
      targets: ["ATProtoLexiconFetcher"]
    ),
    .plugin(
      name: "SwiftAtprotoPlugin",
      targets: ["Generate Source Code"]
    ),
    .plugin(
      name: "ATProtoGenerator",
      targets: ["ATProtoGenerator"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/swift-libp2p/swift-cid", exact: "0.0.1"),
    .package(url: "https://github.com/swift-libp2p/swift-multibase.git", exact: "0.0.2"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.3.1"),
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.19.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
    .package(url: "https://github.com/apple/swift-crypto", exact: "3.10.2"),
    .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.18.0"),
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
      name: "ATProtoCrypto",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "secp256k1", package: "secp256k1.swift"),
        .product(name: "Multibase", package: "swift-multibase"),
      ]
    ),
    .target(
      name: "SwiftAtprotoLex",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .target(name: "SourceControl", condition: .when(platforms: [.macOS, .linux])),
      ]
    ),
    .target(
      name: "SourceControl",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto")
      ]
    ),
    .executableTarget(
      name: "swift-atproto",
      dependencies: [
        "SwiftAtprotoLex",
        .target(name: "SourceControl", condition: .when(platforms: [.macOS, .linux])),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "CommandLineTool"
    ),
    .macro(
      name: "Macros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
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
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "ATProtoCryptoTests",
      dependencies: ["ATProtoCrypto"]
    ),
    .plugin(
      name: "ATProtoLexiconFetcher",
      capability: .command(
        intent: .custom(verb: "swift-atproto-fetch", description: "Fetch AT Protocol lexicons files from remote resources."),
        permissions: [
          .writeToPackageDirectory(reason: "To save the downloaded lexicons to your project."),
          .allowNetworkConnections(scope: .all(ports: [443]), reason: "fetch lexicons"),
        ]
      ),
      dependencies: [.target(name: "swift-atproto")],
    ),
    .plugin(
      name: "Generate Source Code",
      capability: .command(
        intent: .custom(verb: "swift-atproto", description: "Generate source code from AT Protocol definitions."),
        permissions: [
          .writeToPackageDirectory(reason: "This command reformats source files"),
          .allowNetworkConnections(scope: .all(ports: [443]), reason: "fetch lexicons"),
        ]
      ),
      dependencies: [.target(name: "swift-atproto")],
      path: "Plugins/SwiftAtprotoPlugin"),
    .plugin(name: "ATProtoGenerator", capability: .buildTool(), dependencies: ["swift-atproto"]),
  ]
)
