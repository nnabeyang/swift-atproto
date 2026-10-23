import Foundation

/// Exposes the wire fields needed to verify a Permissioned Data repository commit.
///
/// The lexicon generator adds this conformance to `com.atproto.space.defs#commit`
/// when that definition is present and has the expected shape. A commit carries
/// no signature: the repo host authenticates it to a syncer with a MAC in the
/// `Atproto-Space-Mac` response header. Verification is provided by the
/// `ATProtoSync` product.
public protocol PermissionedRepoCommitDescribing: Sendable {
  /// The commit format version.
  var permissionedRepoCommitVersion: Int { get }

  /// The DID of the repo's author.
  var permissionedRepoCommitRepo: FormatString<DID> { get }

  /// The space the repo belongs to.
  var permissionedRepoCommitSpace: FormatString<SpaceRef> { get }

  /// The commit revision.
  var permissionedRepoCommitRevision: FormatString<TID> { get }

  /// The SHA-256 digest claimed for the repository's LtHash state.
  var permissionedRepoCommitData: Data { get }
}

/// Exposes one Permissioned Data repository operation to a sync verifier.
///
/// The lexicon generator adds this conformance to
/// `com.atproto.space.listRepoOps#opEntry` when that definition is present and
/// has the expected shape.
public protocol PermissionedRepoOperationDescribing: Sendable {
  /// The collection containing the affected record.
  var permissionedRepoOperationCollection: FormatString<NSID> { get }

  /// The record key within ``permissionedRepoOperationCollection``.
  var permissionedRepoOperationRecordKey: FormatString<RecordKey> { get }

  /// The record CID after the operation, or `nil` for a deletion.
  var permissionedRepoOperationCID: FormatString<LexLink>? { get }

  /// The record CID before the operation, or `nil` for a creation.
  var permissionedRepoOperationPreviousCID: FormatString<LexLink>? { get }
}
