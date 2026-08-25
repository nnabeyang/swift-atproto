# ``ATProtoSync``

Verify Permissioned Data repository states without owning consumer persistence.

## Overview

`ATProtoSync` authenticates a Permissioned Data signed commit and compares its
hash claim with an ``LtHash`` accumulated from complete records, a DRISL index,
or incremental operations. It does not fetch repositories, parse CAR framing,
or decide how a consumer stores checkpoints.

Generated `com.atproto.space.defs#signedCommit` and
`com.atproto.space.listRepoOps#opEntry` values expose the fields this module
needs, so a consumer can pass generated values directly to ``RepoCommit`` and
``SignedRepoCommitVerifier``.

```swift
var repository = RepoCommit()
for operation in response.ops {
  try repository.apply(operation)
}

if let commit = response.commit {
  try repository.verify(
    commit,
    context: RepoCommitContext(space: space, author: author, revision: revision),
    publicKey: authorKey
  )
}
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

### Signed commits

- ``RepoCommitContext``
- ``SignedRepoCommitVerifier``
- ``RepoVerificationLimits``
- ``RepoVerificationError``
