// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Tools",
    platforms: [.macOS(.v11)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.51.2"),
    ],
    targets: [.target(name: "Tools", path: "")]
)
