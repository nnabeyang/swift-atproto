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
        .package(url: "https://github.com/nnabeyang/swift-atproto", from: "0.37.1"),
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
swift package plugin --allow-writing-to-package-directory \
--allow-network-connections all:443 swift-atproto --outdir <OUTPUT_DIR> --atproto-configuration ./.atproto.json
```

Sample configuration file is as follows. You can specify whether to generate client code, server code, or both using the `generate` field (defaults to `["client"]`).

```json
{
  "generate": ["client", "server"],
  "dependencies": [
    {
      "location": "https://github.com/bluesky-social/atproto.git",
      "lexicons": [
        {
          "prefix": "app.bsky",
          "path": "lexicons/app/bsky",
          "nsIds": [
            "app.bsky.actor.defs",
            "app.bsky.embed.defs",
            "app.bsky.embed.external",
            "app.bsky.embed.images",
            "app.bsky.embed.record",
            "app.bsky.embed.recordWithMedia",
            "app.bsky.embed.video",
            "app.bsky.feed.defs",
            "app.bsky.feed.getPosts",
            "app.bsky.graph.defs",
            "app.bsky.feed.threadgate",
            "app.bsky.labeler.defs",
            "app.bsky.richtext.facet",
            "app.bsky.feed.postgate",
            "app.bsky.notification.defs"
          ]
        },
        {
          "prefix": "com.atproto",
          "path": "lexicons/com/atproto",
          "nsIds": [
            "com.atproto.label.defs",
            "com.atproto.moderation.defs",
            "com.atproto.repo.strongRef"
          ]
        }
      ],
      "state": {
        "tag": "@atproto/api@0.19.3"
      }
    }
  ],
  "module": "Sources/Lexicon"
}
```

## Apps Using

<p float="left">
    <a href="https://apps.apple.com/app/soyokaze/id6738971639"><img src="https://raw.githubusercontent.com/nnabeyang/swift-atproto/refs/heads/main/.github/assets/soyokaze.png" height="65"></a>
</p>

## License

swift-atproto is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://bsky.app/profile/did:plc:bnh3bvyqr3vzxyvjdnrrusbr)
