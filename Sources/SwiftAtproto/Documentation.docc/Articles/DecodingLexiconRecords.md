# Decoding Lexicon records

Choose whether authoring constraints are enforced, check your own values before
sending them, and handle records whose type you do not know.

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
before sending it (see <doc:#Validating-values-before-sending>), and stay
permissive about what you receive.

```swift
let decoder = JSONDecoder()
decoder.userInfo[.atprotoLexiconDecodingMode] = LexiconDecodingMode.strict
let record = try decoder.decode(MyRecord.self, from: data)
```

## Validating values before sending

Every generated object, record, and union conforms to ``LexiconValidatable``.
Call ``LexiconValidatable/validateConstraints()`` on a value you built before
you send it. It checks the same constraints as ``LexiconDecodingMode/strict``
decoding, including those of the values nested in it — the objects a field
refers to, the elements of an array, the value of a union, and a known record
in an `unknown` field — and throws the ``LexiconConstraintError`` that strict
decoding would report:

```swift
let post = App.Bsky.FeedPost(createdAt: now, text: text)
do throws(LexiconConstraintError) {
  try post.validateConstraints()
} catch {
  // `error` names the field and its limit, such as
  // `.tooManyGraphemes("text", limit: 300)`.
}
```

A grapheme limit counts the string's `Character`s, so `text.count` is what the
check compares, while a length limit counts its UTF-8 bytes.

The limits of an array's `items` apply to each element, and an element that
exceeds one is named by its position: the third element of `tags` is reported as
`.tooManyGraphemes("tags[2]", limit: 64)`. A limit on the array itself, such as
its length, is reported under the field's name and checked before the elements.

## Reading the limits

A generated type whose fields declare limits has a nested `Constraints` enum
with one constant per limit, named after the field and the Lexicon keyword:
`textMaxGraphemes` for the `maxGraphemes` of `text`, `videoMaxSize` for the
`maxSize` of `video`. A limit on the elements of an array has `Item` in its
name: `tagsItemMaxGraphemes` for the `maxGraphemes` of each element of `tags`.
The generated checks read the same constants, so the
value you show or compare against is the one that
``LexiconValidatable/validateConstraints()`` and strict decoding enforce, and it
follows the Lexicon when you regenerate.

Use them where a value can't be checked as part of a record yet. A blob's size
is known only after you upload it, so check the file before uploading:

```swift
guard data.count <= App.Bsky.EmbedVideo.Constraints.videoMaxSize else {
  throw VideoTooLarge()
}
// Send this as the input of com.atproto.repo.uploadBlob.
let upload = XRPCBlobUpload(data: data, mimeType: "video/mp4")
```

The parameters of a query have their constants in the `Constraints` enum of the
query's `Input.Query`. The generated client method checks them before it sends
the request.

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
