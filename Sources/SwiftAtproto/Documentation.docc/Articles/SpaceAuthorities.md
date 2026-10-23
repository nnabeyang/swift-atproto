# Resolving space authorities

Find where a space authority answers and which key signs what it issues.

## Overview

> Important: Space authorities come from the permissioned data proposal, not from
> the ratified AT Protocol. How they resolve is the part most likely to change.

Since the October 22, 2026 alpha release, a space authority resolves like any
other account:

- its `#atproto_pds` service entry is where the space host answers
- its `#atproto` verification method signs its space credentials

The `#atproto_space_host` service entry and `#atproto_space` verification method
of the October 1 release are ignored, whatever they point at. Each account that
holds space repos also publishes an `#atproto_kem` verification method, the
P-256 key a syncer encapsulates against to share a MAC secret with its repo host.

## Looking entries up

``DIDDocument/serviceEntry(fragment:)`` and
``DIDDocument/verificationMaterial(fragment:)`` return an entry exactly as the
document publishes it, or `nil` when it is not there. Both accept a relative id
(`#atproto_kem`) or an absolute one (`did:plc:xxx#atproto_kem`), because a
document may write either.

Matching is by id alone. A `type` is required for `#atproto_pds` (see
``DIDDocument/pdsUrl``), but the proposal defines no type string for a syncer's
own service entry.

``DIDDocument/verificationMaterial(fragment:)`` returns the entry rather than a
parsed key, because this module does not depend on `ATProtoCrypto`. Pass the
entry's `publicKeyMultibase` to
`ATProtoCrypto.PublicKey.publicKeyFromMultibaseString(string:)` when you need the
key itself.

## Space roles

| | Entry |
|---|---|
| ``DIDDocument/spaceHostUrl`` | ``DIDDocument/pdsUrl`` |
| ``DIDDocument/spaceSigningKey`` | the `#atproto` key |
| ``DIDDocument/spaceKEMKey`` | the `#atproto_kem` key |

Verification of a token is stricter. A space token names the key that signed it
in its `kid`, and ``DIDDocument/spaceSigningKey(keyId:)`` accepts exactly
`#atproto`: a missing `#`, the retired `#atproto_space`, or any other value is
rejected. Getting that `kid` out of a token in the first place is
<doc:SpaceCredentials>.

## Addressing

``DIDDocument/spaceHostAudience`` is how an authority is addressed when acting as
the space host — the `aud` of a delegation token or client attestation sent to
it, `<did>#atproto_pds`.

For delivery to a specific service, ``ServiceIdentifier`` carries a DID with an
optional fragment naming the entry to deliver to, and
``DIDDocument/endpoint(for:)`` resolves it against the document for that DID. A
bare DID names an account, and an account is served by its PDS, so it resolves
through ``DIDDocument/pdsUrl``.
