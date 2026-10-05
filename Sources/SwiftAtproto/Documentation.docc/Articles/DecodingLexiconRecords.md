# Decoding Lexicon records

Choose whether authoring constraints are enforced, and handle records whose type
you do not know.

## Overview

A Lexicon can constrain a field beyond its type: a maximum string length, a
grapheme count, an array size, an integer range. Generated models can check
those constraints while decoding, but whether they *should* depends on which
side of the wire you are on.

## Strict and permissive

``LexiconDecodingMode`` selects the behavior, and is passed through
`Decoder.userInfo` under the `CodingUserInfoKey.atprotoLexiconDecodingMode`
key this module adds:

- ``LexiconDecodingMode/strict`` enforces every generated constraint and throws
  ``LexiconConstraintError``. This is the default when no mode is set, which
  makes a bare `JSONDecoder()` validating by default.
- ``LexiconDecodingMode/permissive`` accepts wire-compatible values even when
  they exceed an authoring constraint.

Responses decoded by `_XRPCCallable.call(_:input:)` use
``LexiconDecodingMode/permissive`` deliberately. Constraints describe what a
client should *create*; a record already published by another implementation
that exceeds one is still a record you have to display. Validate your own input
before sending it, and stay permissive about what you receive.

```swift
let decoder = JSONDecoder()
decoder.userInfo[.atprotoLexiconDecodingMode] = LexiconDecodingMode.strict
let record = try decoder.decode(MyRecord.self, from: data)
```

## Unknown record types

An `unknown` field can hold any record. Code generation emits a single enum
conforming to ``UnknownATPValueProtocol`` that maps every `$type` it knows to
the matching ``ATProtoRecord``. Decoding dispatches on `$type`:

- A known `$type` decodes into its generated model.
- An unknown `$type` decodes into ``UnknownRecord``, which keeps `$type` and the
  remaining fields as ``AnyCodable`` so the value re-encodes unchanged.
- A value with no `$type` decodes as ``AnyCodable``.

This is what lets a client built against one Lexicon snapshot round-trip records
introduced after it was generated.

## Binary values

A Lexicon `bytes` field is generated as `Data`. In JSON it is written as
`{"$bytes": "<base64>"}`, but only when the encoder is told to: a bare
`JSONEncoder()` writes a plain Base64 string. Set the AT Protocol strategies
whenever you encode or decode Lexicon data outside an XRPC call, such as a
record you store or sign, or a request a server receives:

```swift
let encoder = JSONEncoder()
encoder.dataEncodingStrategy = .atproto

let decoder = JSONDecoder()
decoder.dataDecodingStrategy = .atproto
```

The same encoding strategy writes a ``LexLink`` as `{"$link": "<cid>"}`. A link
reaches the strategy as `Data` — its CID bytes prefixed with `0x00` — so a
`bytes` value with exactly that shape is written as `$link` too.

``LexBlob`` carries a blob reference — its ``LexLink`` CID, MIME type, and size
— rather than the bytes themselves. Uploading bytes is a separate procedure
call; see ``XRPCBlobUpload`` in <doc:MakingXRPCCalls>.
