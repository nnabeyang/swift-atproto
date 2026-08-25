import Foundation

/// Exposes the wire fields needed to verify a Permissioned Data repository commit.
///
/// The lexicon generator adds this conformance to
/// `com.atproto.space.defs#signedCommit` when that definition is present and has
/// the expected shape. Verification is provided by the `ATProtoSync` product.
public protocol PermissionedRepoSignedCommitDescribing: Sendable {
  /// The signed commit format version.
  var permissionedRepoCommitVersion: Int { get }

  /// The SHA-256 digest claimed for the repository's LtHash state.
  var permissionedRepoCommitHash: Data { get }

  /// Per-commit input keying material used for the hash-binding MAC.
  var permissionedRepoCommitInputKeyMaterial: Data { get }

  /// The author's signature over the encoded commit context.
  var permissionedRepoCommitSignature: Data { get }

  /// The HMAC-SHA256 value binding the repository hash to the context.
  var permissionedRepoCommitMAC: Data { get }

  /// The revision encoded in the signed commit.
  var permissionedRepoCommitRevision: FormatString<TID> { get }
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
