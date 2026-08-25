import ATProtoCrypto
import Foundation
import SwiftAtproto

/// A durable, verified position in a Permissioned Data repository.
public struct RepoSyncCheckpoint: Hashable, Sendable {
  /// The revision authenticated by the repository's signed commit.
  public let revision: TID

  /// The repository state at ``revision``.
  public let repository: RepoCommit

  /// The serialized LtHash state for consumer-owned persistence.
  public var state: Data { repository.setHash.state }

  /// Restores a previously persisted checkpoint.
  ///
  /// Only restore bytes that the consumer persisted after successful
  /// verification. This initializer validates the state representation, but
  /// cannot re-authenticate a historical checkpoint without its signed commit.
  public init(revision: TID, state: Data) throws {
    self.revision = revision
    self.repository = try RepoCommit(state: state)
  }

  init(revision: TID, repository: RepoCommit) {
    self.revision = revision
    self.repository = repository
  }
}

/// Why incremental synchronization must restart from a complete repository CAR.
public enum RepoFullStateRecoveryReason: Hashable, Sendable {
  /// The incrementally reconstructed state did not match the authenticated head.
  ///
  /// The current Permissioned Data Lexicon has no distinct history-compaction
  /// signal, so this also represents a missing operation or unavailable history.
  case incrementalStateMismatch
}

/// The terminal result of verifying an incremental repository update.
public enum RepoIncrementalSyncResult: Hashable, Sendable {
  /// The candidate state matched the authenticated repository head.
  case synchronized(RepoSyncCheckpoint)

  /// The candidate state must be discarded and replaced from `getRepo`.
  case fullStateRecoveryRequired(RepoFullStateRecoveryReason)
}

/// An uncommitted candidate state accumulated from incremental repository operations.
///
/// Create a fresh value from the last durable checkpoint, apply every page of
/// `listRepoOps`, and call ``finish(_:context:publicKey:limits:)`` only after a
/// response includes the head signed commit. The base checkpoint remains
/// unchanged unless the returned result supplies a replacement.
public struct RepoIncrementalSync: Hashable, Sendable {
  /// The last durable checkpoint from which this update started.
  public let checkpoint: RepoSyncCheckpoint

  private var candidate: RepoCommit

  /// Starts an incremental update from a durable checkpoint.
  public init(checkpoint: RepoSyncCheckpoint) {
    self.checkpoint = checkpoint
    self.candidate = checkpoint.repository
  }

  /// Validates and applies one generated operation page transactionally.
  ///
  /// If any operation is malformed, none of the operations in this call are
  /// retained in the candidate state.
  public mutating func apply<Operations: Sequence>(_ operations: Operations) throws
  where Operations.Element: PermissionedRepoOperationDescribing {
    var updated = candidate
    try updated.apply(operations)
    candidate = updated
  }

  /// Authenticates the head commit and decides whether the candidate can be persisted.
  ///
  /// Signature, context, and MAC failures are thrown because recovery from the
  /// same unauthenticated source cannot make them trustworthy. Only a valid
  /// commit whose set hash differs from the candidate requests full recovery.
  public func finish(
    _ commit: any PermissionedRepoSignedCommitDescribing,
    context: RepoCommitContext,
    publicKey: PublicKey,
    limits: RepoVerificationLimits = .init()
  ) throws -> RepoIncrementalSyncResult {
    try SignedRepoCommitVerifier.verify(
      commit, context: context, publicKey: publicKey, limits: limits)
    guard context.revision.rawValue >= checkpoint.revision.rawValue else {
      throw RepoVerificationError.staleCommitRevision(
        checkpoint: checkpoint.revision,
        commit: context.revision)
    }
    guard candidate.matches(commit) else {
      return .fullStateRecoveryRequired(.incrementalStateMismatch)
    }
    return .synchronized(
      RepoSyncCheckpoint(revision: context.revision, repository: candidate))
  }
}

extension RepoCommit {
  /// Authenticates this complete state and returns a durable replacement checkpoint.
  ///
  /// For a state built from ``PermissionedRepoCAR/repository``, consume
  /// ``PermissionedRepoCAR/recordBlocks`` through its `nil` terminator before
  /// persisting the returned checkpoint alongside mapped record values.
  public func verifiedCheckpoint(
    _ commit: any PermissionedRepoSignedCommitDescribing,
    context: RepoCommitContext,
    publicKey: PublicKey,
    limits: RepoVerificationLimits = .init()
  ) throws -> RepoSyncCheckpoint {
    try verify(commit, context: context, publicKey: publicKey, limits: limits)
    return RepoSyncCheckpoint(revision: context.revision, repository: self)
  }
}
