# Signing and verifying

Create a key, sign with it, and recover a public key from what a DID document
publishes.

## Overview

``KeyType`` names the three algorithms AT Protocol identities use. Its raw
values are the W3C verification method type names that appear verbatim in a DID
document, which is what lets a document's `type` field select an algorithm:

| Case | Raw value |
|------|-----------|
| ``KeyType/secp256k1`` | `EcdsaSecp256k1VerificationKey2019` |
| ``KeyType/p256`` | `EcdsaSecp256r1VerificationKey2019` |
| ``KeyType/ed25519`` | `Ed25519VerificationKey2020` |

`secp256k1` and `p256` are the two curves AT Protocol uses for repository
signing keys. `ed25519` is supported for reading identities that publish one.

## Creating and storing a key

``PrivateKey/init(type:)`` generates a new key.
``PrivateKey/init(type:rawValue:)`` restores one from bytes previously obtained
from ``PrivateKey/rawRepresentation``, which is the form to persist — the type
is not encoded in the bytes, so store it alongside them.

```swift
let key = try PrivateKey(type: .secp256k1)
let bytes = key.rawRepresentation
// later
let restored = try PrivateKey(type: .secp256k1, rawValue: bytes)
```

## Signing

``PrivateKey/sign(_:)`` returns a signature in the encoding the AT Protocol
expects for that curve: a compact 64-byte ECDSA signature for `secp256k1` and
`p256`, and the Ed25519 signature for `ed25519`.

``PublicKey/isValidSignature(signature:for:)`` verifies one. `secp256k1`
signatures are normalized to low-S before verification, so a high-S signature
produced elsewhere still validates. The method returns `false` for a malformed
signature rather than throwing, so a single call covers both "wrong signature"
and "not a signature at all".

## Public key encodings

``PrivateKey/publicKey`` derives the public half. Two encodings matter:

- ``PublicKey/multibaseString`` is the base58btc multibase form, with the
  multicodec prefix for the key's curve. This is the value a DID document
  publishes as `publicKeyMultibase`.
- ``PublicKey/did`` is the `did:key:` identifier, which is
  ``PublicKey/multibaseString`` with the `did:key:` prefix.

``PublicKey/publicKeyFromMultibaseString(string:)`` reverses the first one,
reading the multicodec prefix to decide the curve. `secp256k1` keys are accepted
in both compressed and uncompressed form and are normalized to compressed.

## Thumbprints

``PublicKey/jwkThumbprint`` is the RFC 7638 JWK thumbprint, base64url-encoded
without padding. It digests the key material alone — the curve, the key type, and
the coordinates — so the two `secp256k1` encodings above give the same
thumbprint, and neither the multibase form nor a `kid` affects it.

A token bound to a key names it this way: comparing a `cnf.jkt` claim against the
thumbprint of a key you hold tells you whether that token was issued for it.

## Reading a key out of a DID document

``Document`` is the parsed DID document. ``Document/getPublicKey(id:)`` finds a
verification method and decodes its key. It accepts a full method id, a
`#fragment` that is resolved against the document's own DID, or an empty string
to take the first method:

```swift
let document = try JSONDecoder().decode(Document.self, from: data)
let signingKey = try document.getPublicKey(id: "#atproto")
```

``VerificationMethod/publicKey`` does the same decoding for a single method. A
`Multikey` method carries the multicodec prefix in its value, so its curve comes
from the value itself; the three curve-specific types name the curve in
``VerificationMethod/type`` instead. A method with no `publicKeyMultibase` —
such as one publishing a JWK — is not supported and throws.
