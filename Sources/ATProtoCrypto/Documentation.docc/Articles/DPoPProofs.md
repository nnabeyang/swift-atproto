# DPoP proofs

Prove possession of the key a space credential is bound to, once per request.

## Overview

> Important: Space credentials come from the permissioned data proposal, not from
> the ratified AT Protocol. What a space host accepts is the part most likely to
> change.

A space credential reads a whole space, and the same credential is presented to
every repo host in that space. As a bearer token it would be a shared secret: a
host handed one to serve its own repo could replay it against every other host in
the space. So the credential is bound to a key its holder alone controls, by the
``PublicKey/jwkThumbprint`` of that key in the credential's `cnf.jkt`, and every
request carries a fresh **DPoP proof** (RFC 9449) signed with the matching
private key.

The proof is what makes the binding mean something. Without it the credential is
still a bearer token; with it, a stolen credential is useless to anyone who does
not also hold the key.

## Building one

``DPoPProof`` holds the claims; ``DPoPProof/signed(with:)`` encodes and signs
them. Each request needs its own, and they come in two shapes, told apart by
whether the proof carries an `ath` claim.

The exchange that obtains a credential proves the key without presenting
anything:

```swift
let proof = DPoPProof(
  httpMethod: "POST",
  url: URL(string: "https://space.example.com/xrpc/com.atproto.space.getSpaceCredential")!,
  issuedAt: Date(),
  tokenID: DPoPProof.randomTokenID())

let jwt = try proof.signed(with: key)
```

Every later request presents the credential it obtained, and says so:

```swift
let proof = DPoPProof(
  httpMethod: "GET",
  url: URL(string: "https://repo.example.com/xrpc/com.atproto.repo.getRecord?rkey=self")!,
  issuedAt: Date(),
  tokenID: DPoPProof.randomTokenID(),
  credential: credential)
```

``DPoPProof/credential`` becomes `ath`, the base64url SHA-256 of the credential's
octets — never the credential itself. A verifier requires `ath` to match what the
request carries, and requires it to be *absent* when no credential is being
presented, so the two cases are not interchangeable.

The signing key has to be the key the credential was bound to. Its public half
travels in the proof's `jwk` header, which is how a verifier checks the signature
without having been told the key in advance; it then compares that key's
thumbprint against the credential's `cnf.jkt`. Only the members RFC 7638 takes a
thumbprint over are embedded — `kty`, `crv`, `x`, and `y` for an EC key — so no
private material and nothing else rides along.

## The target URI

``DPoPProof/httpTargetURI`` is what reaches the wire as `htu`: the URL reduced to
its origin and path. RFC 9449 §4.2 drops the query and the fragment, and that is
not a relaxation a client may decline — an XRPC query carries its parameters in
the query string, so a proof that kept them would never match what the verifier
computes for the same request.

The scheme and host are lowercased and a default port is dropped, for the same
reason: the verifier derives its side of the comparison from a parsed URL and
gets a normalized origin either way.

``DPoPProof/httpMethod`` is not normalized. It is compared verbatim, so it has to
be spelled the way the request line spells it.

A URL with no scheme or no host has no origin to write, and throws
``DPoPProofError/unsupportedTargetURL``.

## Lifetime and replay

A proof covers one method and one URL and is good for one request:

- ``DPoPProof/issuedAt`` becomes `iat`. There is no `exp` — a verifier accepts a
  proof for ``DPoPProof/maximumAge`` past its `iat` and no longer, so a proof
  held onto is a proof about to be rejected. JWT spells `iat` as whole seconds
  since the Unix epoch, so a sub-second part is truncated.
- ``DPoPProof/tokenID`` becomes `jti`, the nonce a verifier remembers in order to
  reject a replay. Never reuse one.
  ``DPoPProof/randomTokenID()`` produces a fresh value: 16 random bytes as
  lowercase hexadecimal.

``DPoPProof/serverNonce`` is absent on the first attempt. If an authorization or
resource server responds with the `use_dpop_nonce` error and a `DPoP-Nonce`
header, store that value for the server and build one new proof with it. The
retry still needs a fresh ``DPoPProof/tokenID``: the server nonce does not make a
proof reusable.

## Algorithms

As with a client attestation, the `alg` header comes from the signing key through
``KeyType/jwsAlgorithm``, and any of the three key types produces a well-formed
proof. What a given verifier accepts is narrower: the space host in the reference
implementation of the proposal accepts `ES256` alone, so a DPoP key is in
practice a ``KeyType/p256`` key.

## What is not here

Verifying a proof is the receiving side of the exchange — checking the signature
against the embedded key, rejecting one whose `iat` is too old, comparing `htm`,
`htu`, and `ath` against the request, and remembering `jti` long enough to catch
a replay. This module signs; it does not verify what someone else signed, and it
keeps no record of what it has issued.

Putting the proof on a request is not here either. `SwiftAtproto` owns the XRPC
transport and does not depend on this module, so the `DPoP` header is set on the
client side of that boundary, with the proof passed across as a string.
