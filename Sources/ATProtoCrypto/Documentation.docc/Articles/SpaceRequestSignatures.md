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
`atproto-space-credential`, the parameter `tag="atproto-space-credential"`, and
the algorithm `ecdsa-p256-sha256`, and writes the signature as the 64-byte `r`
and `s`, not DER, in padded base64.

## Obtaining a credential

`com.atproto.space.getSpaceCredential` carries no signature. The key to bind
the credential to is sent as a `did:key` in the request body's
`credentialKid`, beside the delegation token and client attestation the space
requires. Generate a fresh P-256 key for each new credential and keep it for
the credential's lifetime.

## Presenting a credential

Every request that presents the credential signs `authorization` and then
`atproto-space-audience`, the DID of the host it is addressed to. It names no
key, because the credential's `cnf.kid` already does:

```swift
let signed = try SpaceRequestSignature.use(
  credential: credential, audience: repoHostDID, key: key)
for field in signed.headerFields {
  request.headers[field.name] = field.value
}
// authorization:          Atproto-Space-Credential <credential>
// atproto-space-audience: did:plc:…
// signature-input:        atproto-space-credential=("authorization" "atproto-space-audience");tag="atproto-space-credential"
// signature:              atproto-space-credential=:<base64>:
```

The key has to be the one the credential is bound to. Nothing here checks that,
because the credential is not parsed; `SwiftAtproto` reads `cnf.kid` as
`UnverifiedSpaceCredential.boundKeyID`, which a holder can compare against
``PublicKey/did``.

Which host a request is addressed to, and so which audience it names, is the
caller's to decide, as is how the key is stored between requests.

## Authenticating what a repo host returns

A space repo commit carries no signature either. A syncer reading a repo with a
credential establishes a secret with the repo host for each request and checks
the MAC the response carries:

```swift
let encapsulation = try SpaceKeyEncapsulation.encapsulate(
  authorKEMKey: authorDocument.spaceKEMKey.publicKeyMultibase)
request.headers[.init(SpaceMAC.wantMACHeaderName)!] = SpaceMAC.wantMACHeader(
  type: .repo, keyShare: encapsulation.keyShare)
// … send the request …
let mac = try SpaceMAC.mac(
  fromMACHeader: response.headers[.init(SpaceMAC.macHeaderName)!], type: .repo)
```

Use a new ``SpaceKeyEncapsulation`` for every request, including retries and
each page of a paginated response; it is unrelated to the key the credential is
bound to. `ATProtoSync` verifies a commit with the secret and the MAC.

## Keeping credentials out of logs

``SpaceRequestSignature/authorization`` carries the credential, so
`description` leaves it out, and ``SpaceRequestSignatureError`` carries no part
of it. A value that is empty or contains a line break is refused before
anything is signed, because a line break would let it rewrite the header block
it is written into.
