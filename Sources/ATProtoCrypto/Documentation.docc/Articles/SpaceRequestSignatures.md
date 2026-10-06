# Space request signatures

Prove that a space request comes from the holder of a P-256 key.

## Overview

> Important: Space credentials come from the permissioned data proposal, not from
> the ratified AT Protocol. What a space host accepts is the part most likely to
> change.

A space credential reads a whole space and is presented to every repo host in
it. As a bearer token it would be a shared secret: a host handed one to serve its
own repo could replay it against every other host in the space. So the
credential names a key of its holder's in `cnf.kid`, as a P-256 `did:key`, and
every request that presents it carries an HTTP message signature
([RFC 9421](https://www.rfc-editor.org/rfc/rfc9421.html)) made with that key and
covering the host the request is addressed to. A credential replayed elsewhere
either lacks a signature or carries one for the wrong host.

``SpaceRequestSignature`` produces that signature. It uses the label
`atproto-space` and the algorithm `ecdsa-p256-sha256`, and writes the
signature as the 64-byte `r` and `s`, not DER.

## Obtaining a credential

The exchange that trades a delegation token for a credential signs only the
`authorization` field and names the key in `keyid`. That is how the space
authority learns which key to bind the credential to:

```swift
let signed = try SpaceRequestSignature.exchange(delegationToken: token, key: key)
// authorization:   Bearer <token>
// signature-input: atproto-space=("authorization");keyid="did:key:zDn…"
// signature:       atproto-space=:<base64>:
```

## Presenting a credential

Every later request signs `authorization` and then `atproto-space-audience`, the
DID of the host it is addressed to. It names no key, because the credential's
`cnf.kid` already does:

```swift
let signed = try SpaceRequestSignature.use(
  credential: credential, audience: repoHostDID, key: key)
for field in signed.headerFields {
  request.headers[field.name] = field.value
}
```

The key has to be the one the credential is bound to. Nothing here checks that,
because the credential is not parsed; `SwiftAtproto` reads `cnf.kid` as
`UnverifiedSpaceCredential.boundKeyID`, which a holder can compare against
``PublicKey/did``.

Which host a request is addressed to, and so which audience it names, is the
caller's to decide, as is how the key is stored between requests.

## Keeping credentials out of logs

``SpaceRequestSignature/authorization`` carries the token or the credential, so
`description` leaves it out, and ``SpaceRequestSignatureError`` carries no part
of either. A value that is empty or contains a line break is refused before
anything is signed, because a line break would let it rewrite the header block
it is written into.
