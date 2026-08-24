# swift-atproto

[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnnabeyang%2Fswift-atproto%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/nnabeyang/swift-atproto)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnnabeyang%2Fswift-atproto%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/nnabeyang/swift-atproto)

swift-atproto is a atproto library.

## Installation

### SwiftPM

Add the `SwiftAtproto` as a dependency:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        // other dependencies
        .package(url: "https://github.com/nnabeyang/swift-atproto", from: "0.43.3"),
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

### Usage

Code generation is done using the Swift Package Manager plugin.

#### For Xcode 26.4 / Swift 6.3 and later

The `--disable-experimental-prebuilts` flag is required:

```bash
swift package --disable-experimental-prebuilts plugin \
  --allow-writing-to-package-directory \
  --allow-network-connections all:443 \
  swift-atproto

```

#### For earlier versions (Xcode 26.3 / Swift 6.2.4 and below)

You can run the command without the prebuilts flag:

```bash
swift package plugin \
  --allow-writing-to-package-directory \
  --allow-network-connections all:443 \
  swift-atproto

```


Sample configuration file is as follows. You can specify whether to generate client code, server code, or both using the `generate` field (defaults to `["client"]`).

The same `.atproto.json` schema serves both the `ATProtoGenerator` build tool plugin and the `Generate Source Code` command plugin, but the `module` field behaves differently:

- **Build tool plugin (`ATProtoGenerator`)** writes the generated sources into SwiftPM's plugin work directory. `module` is ignored.
- **Command plugin (`Generate Source Code`)** uses `module` to choose where the generated sources are written in your source tree (e.g. `Sources/Lexicon`).

#### Build plugin sample (no `module`)

```json
{
  "generate": ["client", "server"],
  "dependencies": [
    {
      "location": "https://github.com/bluesky-social/atproto.git",
      "lexicons": [
        {
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
  ]
}
```

#### Command plugin sample (with `module`)

Add `"module": "Sources/Lexicon"` (or the path of your choice) to the same JSON above when invoking `Generate Source Code`:

```json
{
  "generate": ["client", "server"],
  "dependencies": [ ... ],
  "module": "Sources/Lexicon"
}
```

## Documentation

API documentation for the `main` branch is built and hosted by the Swift
Package Index:

- [SwiftAtproto](https://swiftpackageindex.com/nnabeyang/swift-atproto/main/documentation/swiftatproto)
  — the XRPC runtime: the protocols generated code conforms to, the wire
  representations, and the Lexicon string formats.
- [ATProtoCrypto](https://swiftpackageindex.com/nnabeyang/swift-atproto/main/documentation/atprotocrypto)
  — signing keys, their `did:key` encodings, and DID documents.
- [swift-atproto](https://swiftpackageindex.com/nnabeyang/swift-atproto/main/documentation/swift_atproto)
  — the code generation executable the package plugins invoke.

Each target's articles and landing page live in its `Documentation.docc`
catalog (for example `Sources/SwiftAtproto/Documentation.docc`), and the target
list the index publishes is declared in `.spi.yml`.

To build the same documentation locally, reading its target list and parameters
from `.spi.yml`:

```bash
# Build every published target; --strict treats DocC warnings as errors.
./scripts/build-documentation.sh --strict

# Browse one target while editing it.
./scripts/build-documentation.sh --preview SwiftAtproto
```

The generated documentation is not committed; the Swift Package Index rebuilds
it from source.

## Apps Using

- [Soyokaze](https://apps.apple.com/app/soyokaze/id6738971639) — Bluesky client for iOS
- [tng](https://tangled.org/nnabeyang.tngl.sh/swift-tangled) — CLI for Tangled
- [spindle-agent](https://tangled.org/nnabeyang.tngl.sh/spindle-agent) — External macOS worker for Tangled Spindle
- [atproto-oauth-tmb](https://tangled.org/nnabeyang.tngl.sh/atproto-oauth-tmb) — A single-tenant AT Protocol OAuth Token-Mediating Backend in Swift

## License

swift-atproto is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://bsky.app/profile/did:plc:bnh3bvyqr3vzxyvjdnrrusbr)
