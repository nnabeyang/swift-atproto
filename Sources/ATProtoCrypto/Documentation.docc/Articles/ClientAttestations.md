# Client attestations

Sign the JWT that tells a space authority which application is asking.

## Overview

Permissioned data separates two questions an authority has to answer before it
issues a space credential: *which user* is being acted for, and *which
application* is acting. A delegation token, signed by the user's PDS, answers the
first. A **client attestation**, signed by the application itself, answers the
second. They are presented together but signed by different parties and
evaluated independently.

Only spaces that gate on client app identity ask for an attestation. A space open
to any application does not, which is what lets public clients — the ones with no
key to sign with — reach it at all.

An attestation is structurally a `private_key_jwt` client assertion, the same
shape an AT Protocol confidential client already presents to its authorization
server. The difference is where it is addressed: a space host rather than an
authorization server, named by the `#atproto_space_host` entry of the authority's
DID document.

## Building one

``ClientAttestation`` holds the claims; ``ClientAttestation/signed(with:)``
encodes and signs them:

```swift
let now = Date()
let attestation = ClientAttestation(
  clientID: "https://app.example.com/client-metadata.json",
  audience: "did:example:space_did#atproto_space_host",
  keyID: "key-1",
  issuedAt: now,
  expiresAt: now.addingTimeInterval(60),
  tokenID: ClientAttestation.randomTokenID())

let jwt = try attestation.signed(with: key)
```

``ClientAttestation/clientID`` is the URL the application publishes its client
metadata at. It is written to both `iss` and `sub`, which a client assertion
requires to carry the same value, so there is no way to make the two disagree.

``ClientAttestation/audience`` names the space host. `SwiftAtproto` derives it
from a resolved DID document as `DIDDocument.spaceHostAudience`, which is always
that document's DID with the `#atproto_space_host` fragment, whether or not the
document declares such an entry. It is taken as a string here because
`ATProtoCrypto` does not depend on that module.

``ClientAttestation/keyID`` becomes the `kid` header. The authority resolves
``ClientAttestation/clientID`` to the client metadata document, fetches the JWKS
it publishes, and verifies the signature against the key that `kid` names — so it
has to name the public half of the key passed to
``ClientAttestation/signed(with:)``. That pairing cannot be checked here, because
this module never sees the JWKS.

## Lifetime and replay

An attestation is short-lived and single-use, so neither its lifetime nor its
nonce is filled in for you:

- ``ClientAttestation/issuedAt`` and ``ClientAttestation/expiresAt`` become `iat`
  and `exp`. A minute is a typical span. JWT spells both as whole seconds since
  the Unix epoch, so a sub-second part is truncated.
- ``ClientAttestation/tokenID`` becomes `jti`, the nonce an authority remembers
  in order to reject a repeat. Never reuse one.
  ``ClientAttestation/randomTokenID()`` produces a fresh value: 16 random bytes
  as lowercase hexadecimal.

## Algorithms

The `alg` header comes from the signing key rather than the caller, through
``KeyType/jwsAlgorithm``:

| ``KeyType`` | `alg` |
|-------------|-------|
| ``KeyType/p256`` | `ES256` |
| ``KeyType/secp256k1`` | `ES256K` |
| ``KeyType/ed25519`` | `EdDSA` |

``PrivateKey/sign(_:)`` already produces what each of these requires: the two
ECDSA cases hash with SHA-256 and return the 64-byte `r‖s` concatenation JWS
asks for, and Ed25519 signs the message directly.

## What is not here

Verifying an attestation is the authority's side of the exchange — resolving a
`client_id` to its metadata, fetching a JWKS over the network, and checking a
signature against a key found there. This module signs; it makes no network
requests and does not verify what someone else signed.
