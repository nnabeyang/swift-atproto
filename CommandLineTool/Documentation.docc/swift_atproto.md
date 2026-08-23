# ``swift_atproto``

Generate Swift code from AT Protocol Lexicon files.

@Metadata {
  @DisplayName("swift-atproto")
}

## Overview

`swift-atproto` reads an `.atproto.json` configuration, fetches the Lexicon JSON
it depends on, and writes type-safe Swift sources for XRPC clients and servers.

You normally do not run it yourself. The `Generate Source Code` command plugin
and the `ATProtoGenerator` build tool plugin both invoke this executable, and
the plugins are the supported entry points because they arrange package
permissions for network access and for writing into the package directory.

```bash
swift package --disable-experimental-prebuilts plugin \
  --allow-writing-to-package-directory \
  --allow-network-connections all:443 \
  swift-atproto
```

Drop `--disable-experimental-prebuilts` on Swift 6.2.4 and earlier.

## Running the command directly

Invoking the executable is useful when debugging generation, since it reports
errors without the plugin sandbox in between.

```bash
swift run swift-atproto --atproto-configuration .atproto.json
```

### Options

- term `--atproto-configuration <path>`:
  The `.atproto.json` to read. Required. Its directory is treated as the
  package root, which is what `--outdir` is resolved against when the
  configuration supplies a relative `module`.

- term `--outdir <path>`:
  Where to write the generated sources. Defaults to the `module` directory named
  by the configuration, resolved against the configuration's own directory.

- term `--fetch-only`:
  Fetch the Lexicon files and stop without generating anything. This is what the
  `ATProtoLexiconFetcher` plugin runs.

- term `--version`:
  Print the version and exit.

There is also a hidden `--plugin-source` option. It exists so the build tool
plugin can tell the command it is not being run interactively, and it is not
meant for manual use; `--help-hidden` lists it.

## What it generates

For each configured Lexicon namespace the command writes:

- `UnknownATPValue.swift` — the enum that dispatches a decoded `$type` back to
  its generated record type.
- `XRPCAPIClient.swift` — the client-side call methods.
- `XRPCAPIProtocol.swift` — the server-side protocol, when `generate` includes
  `"server"`.

Generated files carry a `// DO NOT EDIT` header. Change the Lexicon or the
configuration and regenerate rather than editing them.

## Configuration

See the project README for the `.atproto.json` schema. The field that differs
between entry points is `module`: the command plugin uses it to choose a
destination inside your source tree, while the build tool plugin ignores it and
writes into SwiftPM's plugin work directory.
