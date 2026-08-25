# ``ATProtoSync``

Verify Permissioned Data repository states without owning consumer persistence.

## Overview

`ATProtoSync` authenticates a Permissioned Data signed commit and compares its
hash claim with an ``LtHash`` accumulated from complete records, a DRISL index,
or incremental operations. It also verifies the two roots and blocks in a
streaming Permissioned Data repository CAR. It does not fetch repositories or
decide how a consumer maps records and stores checkpoints.

Generated `com.atproto.space.defs#signedCommit` and
`com.atproto.space.listRepoOps#opEntry` values expose the fields this module
needs, so a consumer can pass generated values directly to ``RepoCommit`` and
``SignedRepoCommitVerifier``.

```swift
let checkpoint = try RepoSyncCheckpoint(revision: persistedRevision, state: persistedState)
var update = RepoIncrementalSync(checkpoint: checkpoint)
try update.apply(response.ops)

if let commit = response.commit {
  let result = try update.finish(
    commit,
    context: RepoCommitContext(space: space, author: author, revision: revision),
    publicKey: authorKey
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
`com.atproto.space.getRepo` call directly to ``PermissionedRepoCAR``. The
signed commit and repository index are available immediately; record blocks
remain pull-driven and are checked against their CIDs as they are consumed.

```swift
let response = try await client.SpaceGetRepoStreaming(repo: repo, space: space)
let car = try await PermissionedRepoCAR.read(from: response.body)

let commit = try SignedRepoCommitVerifier.decode(
  Com.Atproto.SpaceDefs_SignedCommit.self,
  fromDRISL: car.signedCommitBlock.bytes
)
let context = RepoCommitContext(
  space: expectedSpace,
  author: repositoryAuthor,
  revision: try TID(string: commit.permissionedRepoCommitRevision.rawValue)
)
try car.repository.verify(
  commit,
  context: context,
  publicKey: authorPublicKey
)

for try await record in car.recordBlocks {
  // Map the index-verified path and CID-verified value into consumer-owned storage.
}
let replacement = try car.repository.verifiedCheckpoint(
  commit,
  context: context,
  publicKey: authorPublicKey
)
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

- ``PermissionedRepoCAR``
- ``PermissionedRepoCARBlock``
- ``PermissionedRepoCARRecord``

### Signed commits

- ``RepoCommitContext``
- ``SignedRepoCommitVerifier``
- ``RepoVerificationLimits``
- ``RepoVerificationError``
