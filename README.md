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

Code generation is done as follows:
```bash
swift package plugin --allow-writing-to-package-directory swift-atproto \
  --outdir <OUTPUT_DIR> \
  /path/to/bluesky-social/atproto/lexicons
```

`swift-atproto` supports code generation from the Lexicon up to the [@atproto/api@0.7.2](https://github.com/bluesky-social/atproto/pull/1946) tag in the repository `bulue-social/atproto`.

## License

swift-atproto is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://bsky.app/profile/nnabeyang.bsky.social)
