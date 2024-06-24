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
        .package(url: "https://github.com/nnabeyang/swift-atproto", from: "0.12.0"),
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
swift package plugin --allow-writing-to-package-directory swift-atproto --outdir <OUTPUT_DIR> --atproto-configuration ./.atproto.json
```

Sample configuration file is as follows:
```json
{
  "dependencies": [
    {
      "location": "https://github.com/bluesky-social/atproto.git",
      "lexicons": [
        { "prefix": "app.bsky", "path": "lexicons/app/bsky" },
        { "prefix": "com.atproto", "path": "lexicons/com/atproto" }
      ],
      "state": {
        "tag": "@atproto/api@0.12.18"
      }
    },
    {
      "location": "https://github.com/whtwnd/whitewind-blog.git",
      "lexicons": [{ "prefix": "com.whtwnd", "path": "lexicons/com/whtwnd" }],
      "state": {
        "tag": "v1.0.1"
      }
    }
  ]
}
```

## License

swift-atproto is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://bsky.app/profile/did:plc:bnh3bvyqr3vzxyvjdnrrusbr)
