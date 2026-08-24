# Reading space credentials

Read what a space token says without pretending to know that it is genuine.

## Overview

> Important: Space credentials come from the permissioned data proposal, not from
> the ratified AT Protocol.

Permissioned data introduces three JWT credential classes. An application signs
one of them itself and receives the other two, and what it does with each one
depends on reading a handful of claims out of it.

| Credential | Signed by | The application |
|------------|-----------|-----------------|
| delegation token | the user's PDS | forwards it to the space authority |
| client attestation | the application | signs it and sends it |
| space credential | the space authority | holds it and reads it |

``UnverifiedSpaceCredential``, ``UnverifiedSpaceDelegationToken``, and
``UnverifiedClientAttestation`` each take a compact JWT and give back its claims:

```swift
let credential = try UnverifiedSpaceCredential(introspecting: jwt)

credential.issuer              // DID — the space authority
credential.space               // SpaceRef — the space it reads
credential.boundKeyThumbprint  // String — the key it is bound to
credential.expiresAt           // Date
```

## Nothing here is verified

Reading a token establishes only that it is well-formed. It says nothing about
who signed it, because checking that means resolving the issuer to a DID
document, taking the key the token names, and testing the signature against it —
a network round trip and a decision that belongs to the service the token is
addressed to, not to the party holding it.

That is why every type is named `Unverified…` and every initializer is labelled
`introspecting:`: a value read out of a token must never be mistaken at a call
site for one that was verified.

``UnverifiedSpaceCredential/keyID`` is the near end of the verifying side. It
carries the token's `kid`, which
``DIDDocument/spaceSigningKey(keyId:)`` resolves to the entry that published the
key. Turning that entry into a key means handing its `publicKeyMultibase` to
`ATProtoCrypto`, which this module does not depend on. See
<doc:SpaceAuthorities> for the resolution rules.

## What each class requires

The three share a wire shape and differ only in who signs them, who they are
addressed to, and how long they live:

| Credential | `typ` | `aud` | `cnf.jkt` | `jti` |
|------------|-------|-------|-----------|-------|
| delegation token | `atproto-space-delegation+jwt` | required | — | required |
| client attestation | `atproto-client-attestation+jwt` | required | — | required |
| space credential | `atproto-space-credential+jwt` | — | required | optional |

`alg`, `iss`, `sub`, and `exp` are required of all three. A missing one throws
``SpaceTokenError/missingClaim(_:)``; a claim that is present but malformed
throws the error of its own identifier type, so an `iss` that is not a DID fails
as ``LexiconStringFormatError`` rather than being smuggled through as a string.

A credential carries no `aud` because it is presented to every repo host serving
a repo in the space, and no host is named in advance. It is bound to the holder's
DPoP key instead. It also needs no `jti`: a nonce exists so a recipient can
refuse a replay, and a credential is meant to be reused.

A client attestation writes the `client_id` into both `iss` and `sub`, so
``UnverifiedClientAttestation/clientID`` is one property rather than two, and a
token whose two disagree is rejected with
``SpaceTokenError/clientIDMismatch``.

## Using a credential

Three questions a holder asks, in the order they come up:

```swift
// Is it still worth sending?
credential.isExpired()

// Is it for the space I asked about?
credential.authorizes(requestedSpace)

// Is it bound to my key?
credential.isBound(toKeyThumbprint: myKeyThumbprint)
```

``UnverifiedSpaceCredential/isExpired(at:clockSkew:)`` applies five seconds of
clock skew by default, and it applies them in the permissive direction: the
credential still counts as live for five seconds past
``UnverifiedSpaceCredential/expiresAt``, so a clock running slightly fast does
not throw away a credential the issuer considers valid. A holder deciding when to
renew wants the opposite, and asks for it by passing a negative skew:

```swift
// Renew a minute before it lapses.
if credential.isExpired(clockSkew: -60) { … }
```

``UnverifiedSpaceCredential/isBound(toKeyThumbprint:)`` compares against the RFC
7638 thumbprint of the holder's own DPoP key, which `ATProtoCrypto` computes.
Thumbprints are base64url, so the comparison is exact and case-sensitive.

## Keeping credentials out of logs

A credential is a capability. These types are built so that handling one does not
leak it:

- None of them conforms to `Codable`, so a credential does not fall into a state
  file by being a stored property of something that does.
- None of them keeps the JWT it was read from.
- ``SpaceTokenError`` carries no part of a token, so an error is safe to log.
- `description` names the space and the expiry and stops. The reflected
  description Swift would print by default includes `cnf.jkt` and `jti`, which is
  exactly how a credential reaches a log.

## The other direction

Signing a client attestation is `ATProtoCrypto.ClientAttestation`, in the module
that holds the keys. The two sides never share a type — they meet as a JWT
string — so the introspection here works on an attestation regardless of who
produced it.
