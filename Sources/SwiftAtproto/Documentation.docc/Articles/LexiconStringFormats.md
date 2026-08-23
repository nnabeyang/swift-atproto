# Lexicon string formats

Keep the wire string, and interpret it only when you need a value.

## Overview

A Lexicon `string` field can declare a `format` such as `did`, `handle`,
`at-uri`, or `datetime`. Each of those maps to a type conforming to
``LexiconStringFormat``, which validates a string and exposes the canonical form
as ``LexiconStringFormat/rawValue``.

Generated models do not store those types directly. They store
``FormatString``, which is generic over the format:

```swift
public struct FormatString<T: LexiconStringFormat>: RawRepresentable, Codable, Hashable, Sendable
```

## Why the raw string is preserved

``FormatString`` decodes and encodes as a plain `String` and keeps the wire
value verbatim. A record that arrives with a value this library would reject
still round-trips byte-for-byte, and a record signed by another implementation
keeps its signature valid.

Interpretation is separate and failable:

- ``FormatString/typed`` parses strictly and returns `nil` when the value does
  not satisfy the format.
- ``FormatString/typedLenient`` parses with the format's relaxed rules, for
  formats that define one.

Equality and hashing use ``FormatString/rawValue``, not the parsed value.
Two values that mean the same instant but differ in spelling are not equal as
``FormatString``s; compare ``FormatString/typed`` to compare by value.

```swift
let createdAt: FormatString<Date> = record.createdAt

createdAt.rawValue          // exactly what the server sent
createdAt.typed             // Date?, strict AT Protocol datetime
createdAt.typedLenient      // Date?, accepts the relaxed spelling
```

## Strict and lenient

``LexiconStringFormat`` has two initializers. `init(string:)` is always strict.
`init(string:strict:)` defaults to calling the strict one, so identifier formats
that have no relaxed reading — ``DID``, ``Handle``, ``NSID``, ``TID`` — behave
identically either way.

`Date` is the format where the distinction is widest. The AT Protocol datetime
grammar is narrower than ISO 8601: strict parsing requires the full form the
spec mandates, while lenient parsing accepts the older spellings that existing
records contain. Because decoding a response uses
``LexiconDecodingMode/permissive``, a value that only parses leniently still
arrives intact and is yours to interpret.

``RecordKey`` relaxes too, dropping its length and character limits and keeping
only what AT URI path syntax requires. ``SpaceRef`` carries that relaxation into
its space key and ``ATURI`` into both key segments, the latter additionally
accepting a trailing slash, a query string, and a malformed percent-escape in a
fragment.

## Validation is about shape

These types check that a string is well-formed, not that it refers to anything.
``Handle`` verifies the DNS-like label grammar and length limits without
resolving the handle or canonicalizing an internationalized domain;
``DID`` checks method syntax without dereferencing the identifier. Confirming
that a handle belongs to a DID is a separate step — see ``DIDDocument`` and
``DIDHandleResolver``.
