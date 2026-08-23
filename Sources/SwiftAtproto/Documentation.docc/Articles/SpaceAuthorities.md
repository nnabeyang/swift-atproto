# Resolving space authorities

Find where a space authority answers and which key signs what it issues.

## Overview

> Important: Space authorities come from the permissioned data proposal, not from
> the ratified AT Protocol. The fallback rules below are the part most likely to
> change.

A space authority is reached through two optional entries in its DID document:

- an `#atproto_space_host` service entry — where the space host answers
- an `#atproto_space` verification method — the key its space credentials are
  signed with

Neither is required. When an entry is absent the authority is reached through the
account's own `#atproto_pds` service entry and `#atproto` verification method
instead, so an authority that runs no dedicated infrastructure still resolves.

## Looking entries up

``DIDDocument/serviceEntry(fragment:)`` and
``DIDDocument/verificationMaterial(fragment:)`` return an entry exactly as the
document publishes it, or `nil` when it is not there. Both accept a relative id
(`#atproto_space`) or an absolute one (`did:plc:xxx#atproto_space`), because a
document may write either.

Matching is by id alone. A `type` is required for `#atproto_pds` (see
``DIDDocument/pdsUrl``), but the proposal defines no type string for a space host
or for a syncer's own service entry.

``DIDDocument/verificationMaterial(fragment:)`` returns the entry rather than a
parsed key, because this module does not depend on `ATProtoCrypto`. Pass the
entry's `publicKeyMultibase` to
`ATProtoCrypto.PublicKey.publicKeyFromMultibaseString(string:)` when you need the
key itself.

## Falling back

``DIDDocument/spaceHostUrl`` and ``DIDDocument/spaceSigningKey`` apply the
proposal's fallbacks:

| | Published | Absent |
|---|---|---|
| ``DIDDocument/spaceHostUrl`` | the `#atproto_space_host` endpoint | ``DIDDocument/pdsUrl`` |
| ``DIDDocument/spaceSigningKey`` | the `#atproto_space` key | the `#atproto` key |

A published-but-malformed endpoint throws rather than falling back. The fallback
is for an authority that declares no dedicated host; quietly routing past a
misconfigured one would send space-host traffic to the PDS.

Verification is the other direction and does not fall back. A space token names
the key that signed it in its `kid`, so
``DIDDocument/spaceSigningKey(keyId:)`` resolves that key and treats a missing
entry as an error. Only `atproto` and `atproto_space` are accepted.

## Addressing

``DIDDocument/spaceHostAudience`` is how an authority is addressed when acting as
the space host — the `aud` of a delegation token or client attestation sent to
it. It is the audience, not the destination: an authority that publishes no
`#atproto_space_host` entry is still addressed this way while being reached at
its PDS.

For delivery to a specific service, ``ServiceIdentifier`` carries a DID with an
optional fragment naming the entry to deliver to, and
``DIDDocument/endpoint(for:)`` resolves it against the document for that DID. A
bare DID names an account, and an account is served by its PDS, so it resolves
through ``DIDDocument/pdsUrl``.
