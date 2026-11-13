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
covering the audience the request is addressed to. A credential replayed
elsewhere either lacks a signature or carries one for the wrong audience.

``SpaceRequestSignature`` produces that signature. It uses the label `sig`,
the parameter `tag="atproto-space-credential"`, and the algorithm
`ecdsa-p256-sha256`, and writes the signature as the 64-byte `r` and `s`, not
DER, in padded base64. A host finds the signature by its tag, not its label.

## Obtaining a credential

`com.atproto.space.authorizeSpaceSync` carries no signature. The key to bind
the credential to is sent as a `did:key` in the request body's
`credentialKey`, beside the delegation token and client attestation the space
requires. Generate a fresh P-256 key for each new credential and keep it for
the credential's lifetime.

## Presenting a credential

Every request that presents the credential signs `authorization` and then
`atproto-space-audience`. When syncing a repo, the audience is the DID of the
account the repo belongs to; for a request to the space host, it is the space
authority's DID. The signature names no key, because the credential's
`cnf.kid` already does:

```swift
let signed = try SpaceRequestSignature.use(
  credential: credential, audience: repoOwnerDID, key: key)
for field in signed.headerFields {
  request.headers[field.name] = field.value
}
// authorization:          Atproto-Space-Credential <credential>
// atproto-space-audience: did:plc:…
// signature-input:        sig=("authorization" "atproto-space-audience");tag="atproto-space-credential"
// signature:              sig=:<base64>:
```

The key has to be the one the credential is bound to. Nothing here checks that,
because the credential is not parsed; `SwiftAtproto` reads `cnf.kid` as
`UnverifiedSpaceCredential.boundKeyID`, which a holder can compare against
``PublicKey/did``.

Which audience a request names, and how the key is stored between requests,
are the caller's to decide.

## Authenticating what a repo host returns

A space repo commit carries no signature either. A syncer reading a repo with a
credential shares a secret with the repo host for each request, asks for a MAC
in `Accept-Signature`, and checks the MAC the response carries. The MAC is an
HTTP message signature with the `hmac-sha256` algorithm, keyed by that secret,
over a field that describes the commit or record:

```swift
let encapsulation = try SpaceKeyEncapsulation.encapsulate(
  authorKEMKey: authorDocument.spaceKEMKey.publicKeyMultibase)
request.headers[.init(SpaceMAC.acceptSignatureFieldName)!] = SpaceMAC.acceptSignature(
  profile: .commit, keyShare: encapsulation.keyShare)
// accept-signature: mac=("atproto-space-commit";sf);keyid="did:key:zDna…";tag="atproto-space-commit"
// … send the request …
let mac = SpaceMACResponse(profile: .commit) { response.headers[.init($0)!] }
```

The response carries `Atproto-Space-Commit`, which repeats the commit's
fields, and a `Signature-Input` and `Signature` covering exactly that field.
``SpaceMAC/verifyCommit(_:commit:encapsulation:)`` finds the signature by its
`tag`, checks it, and checks that the field describes the commit in the
response body; `ATProtoSync` does this for you. For `getRecord`, request the
``SpaceMACProfile/record`` profile and check the response with
``SpaceMAC/verifyRecord(_:record:encapsulation:)``, passing the URI that was
requested and the CID computed from the returned record.

Use a new ``SpaceKeyEncapsulation`` for every request, including retries and
each page of a paginated response; it is unrelated to the key the credential is
bound to. If a MAC does not verify, refresh the author's DID document before
retrying with a new encapsulation.

A repo host reads the request with
``SpaceMAC/request(fromAcceptSignature:profile:)``, derives the secret with
``SpaceKeyEncapsulation/decapsulate(keyShare:authorKEMKey:)``, and answers with
``SpaceMAC/responseFields(commit:request:sharedSecret:)`` or
``SpaceMAC/responseFields(record:request:sharedSecret:)``.

## Keeping credentials out of logs

``SpaceRequestSignature/authorization`` carries the credential, so
`description` leaves it out, and ``SpaceRequestSignatureError`` carries no part
of it. A value that is empty or contains a line break is refused before
anything is signed, because a line break would let it rewrite the header block
it is written into.
