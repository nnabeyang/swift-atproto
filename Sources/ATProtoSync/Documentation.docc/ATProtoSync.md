# ``ATProtoSync``

Verify Permissioned Data repository states without owning consumer persistence.

## Overview

`ATProtoSync` authenticates a Permissioned Data commit with the MAC its
response carried and compares its `data` with an ``LtHash`` accumulated from
complete records or incremental operations. It also reads the STAR archive
`getRepo` returns. It does not fetch repositories or decide how a consumer maps
records and stores checkpoints.

A commit carries no signature. For each request, the syncer shares a secret
with the repo host through `ATProtoCrypto.SpaceKeyEncapsulation`, sends the key
share in `Atproto-Space-Want-Mac`, and reads the MAC from `Atproto-Space-Mac`.
``RepoCommitAuthentication`` carries what was requested, the secret, and that
MAC. Generated `com.atproto.space.defs#commit` and
`com.atproto.space.listRepoOps#opEntry` values expose the fields this module
needs, so a consumer can pass generated values directly to ``RepoCommit`` and
``RepoCommitVerifier``.

```swift
let checkpoint = try RepoSyncCheckpoint(revision: persistedRevision, state: persistedState)
var update = RepoIncrementalSync(checkpoint: checkpoint)
try update.apply(response.ops)

if let commit = response.commit {
  let result = try update.finish(
    commit,
    authentication: RepoCommitAuthentication(
      space: space, repo: author, sharedSecret: encapsulation.sharedSecret, mac: mac)
  )
  switch result {
  case .synchronized(let replacement):
    // Persist replacement.revision and replacement.state atomically.
  case .fullStateRecoveryRequired:
    // Discard the candidate and restart from getRepo.
  }
}
```

For full-state recovery, pass the body returned by a generated streaming
`com.atproto.space.getRepo` call directly to ``PermissionedRepoSTAR``. The
metadata commit is authenticated before `read` returns; records remain
pull-driven and are folded into a set hash as they are consumed.

```swift
let star = try await PermissionedRepoSTAR.read(
  from: response.body,
  authentication: RepoCommitAuthentication(
    space: space, repo: author, sharedSecret: encapsulation.sharedSecret, mac: mac))

for try await record in star.records {
  // Stage the path-ordered, CID-computed record in consumer-owned storage.
}
let replacement = try star.verifiedCheckpoint()
// Replace records and persist replacement only after the record stream reaches its end.
```

The internal BLAKE3 implementation is upstream BLAKE3 1.8.7, distributed
under Apache License 2.0. Applications distributing binaries containing this
target need to reproduce that license as part of their third-party notices;
see `THIRD_PARTY_NOTICES.md` in the package repository.

## Topics

### Repository state

- ``LtHash``
- ``RepoCommit``
- ``RepoRecord``
- ``RepoOperation``
- ``RepoSyncCheckpoint``
- ``RepoIncrementalSync``
- ``RepoIncrementalSyncResult``
- ``RepoFullStateRecoveryReason``

### Full-state recovery

- ``PermissionedRepoSTAR``
- ``PermissionedRepoSTARCommit``
- ``PermissionedRepoSTARRecord``

### Commits

- ``RepoCommitAuthentication``
- ``RepoCommitVerifier``
- ``RepoVerificationLimits``
- ``RepoVerificationError``
