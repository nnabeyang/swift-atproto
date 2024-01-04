# swift-atproto

swift-atproto is a atproto library.

## Installation

### SwiftPM

Add the `SwiftAtproto` as a dependency:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        // other dependencies
        .package(url: "https://github.com/nnabeyang/swift-atproto", from: "0.4.2"),
    ],
    targets: [
        .executableTarget(name: "<executable-target-name>", dependencies: [
            // other dependencies
                .product(name: "SwiftAtproto", package: "swift-atproto"),
        ]),
        // other targets
    ]
)
```

### CocoaPods

Add the following to your Podfile:

```terminal
pod 'SwiftAtproto'
```

### Usage

[nnabeyang/swiftsky](https://github.com/nnabeyang/swiftsky) uses swift-atproto to generate the code to implement the XRPC protocol.
In the case of swiftsky, code generation is done as follows:
```bash
git clone https://github.com/nnabeyang/swift-atproto
git clone https://github.com/nnabeyang/swiftsky
cd swift-atproto
make lexgen
```

## License

swift-atproto is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://bsky.app/profile/nnabeyang.bsky.social)
