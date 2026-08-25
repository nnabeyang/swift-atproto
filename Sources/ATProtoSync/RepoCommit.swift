import ATProtoCrypto
import Foundation
import SwiftAtproto

/// A record path and CID folded into a Permissioned Data repository state.
public struct RepoRecord: Hashable, Sendable {
  /// The record's collection.
  public let collection: NSID

  /// The record key within ``collection``.
  public let recordKey: RecordKey

  /// The CID of the record value.
  public let cid: LexLink

  /// Creates a repository record reference.
  public init(collection: NSID, recordKey: RecordKey, cid: LexLink) {
    self.collection = collection
    self.recordKey = recordKey
    self.cid = cid
  }
}

/// A create, update, or delete applied to a Permissioned Data repository state.
public struct RepoOperation: Hashable, Sendable {
  /// The affected record's collection.
  public let collection: NSID

  /// The affected record's key.
  public let recordKey: RecordKey

  /// The record CID after the operation, or `nil` for a deletion.
  public let cid: LexLink?

  /// The record CID before the operation, or `nil` for a creation.
  public let previousCID: LexLink?

  /// Creates an operation with at least one current or previous CID.
  ///
  /// - Throws: ``RepoVerificationError/malformedOperation`` when both CIDs are
  ///   absent.
  public init(
    collection: NSID,
    recordKey: RecordKey,
    cid: LexLink?,
    previousCID: LexLink?
  ) throws {
    guard cid != nil || previousCID != nil else {
      throw RepoVerificationError.malformedOperation
    }
    self.collection = collection
    self.recordKey = recordKey
    self.cid = cid
    self.previousCID = previousCID
  }
}

/// The running LtHash state for a Permissioned Data repository.
public struct RepoCommit: Hashable, Sendable {
  /// The repository's homomorphic set hash.
  public private(set) var setHash: LtHash

  /// Creates an empty repository state.
  public init() {
    setHash = LtHash()
  }

  /// Restores a repository from a persisted LtHash state.
  public init(state: Data) throws {
    setHash = try LtHash(state: state)
  }

  /// Builds a repository state from complete record references.
  public init<Records: Sequence>(records: Records) where Records.Element == RepoRecord {
    self.init()
    for record in records {
      add(record)
    }
  }

  /// Builds a repository state from a canonical DRISL index block.
  ///
  /// Index keys use `collection/rkey`; values are CID links. The input limits
  /// bound both encoded allocation and the number of records folded into the
  /// state.
  public init(
    drislIndex data: Data,
    limits: RepoVerificationLimits = .init()
  ) throws {
    self.init(records: try PermissionedRepoIndex(drisl: data, limits: limits).records)
  }

  /// Adds a complete record reference to the state.
  public mutating func add(_ record: RepoRecord) {
    setHash.add(Self.element(for: record))
  }

  /// Removes a complete record reference from the state.
  public mutating func remove(_ record: RepoRecord) {
    setHash.remove(Self.element(for: record))
  }

  /// Applies a typed create, update, or delete operation.
  public mutating func apply(_ operation: RepoOperation) {
    if let previousCID = operation.previousCID {
      remove(
        RepoRecord(
          collection: operation.collection,
          recordKey: operation.recordKey,
          cid: previousCID))
    }
    if let cid = operation.cid {
      add(
        RepoRecord(
          collection: operation.collection,
          recordKey: operation.recordKey,
          cid: cid))
    }
  }

  /// Validates and applies an operation produced from a Permissioned Data lexicon.
  public mutating func apply(_ operation: any PermissionedRepoOperationDescribing) throws {
    guard
      let collection = operation.permissionedRepoOperationCollection.typed,
      let recordKey = operation.permissionedRepoOperationRecordKey.typed
    else {
      throw RepoVerificationError.malformedOperation
    }
    let cid = try Self.validatedLink(operation.permissionedRepoOperationCID)
    let previousCID = try Self.validatedLink(
      operation.permissionedRepoOperationPreviousCID)
    apply(
      try RepoOperation(
        collection: collection,
        recordKey: recordKey,
        cid: cid,
        previousCID: previousCID))
  }

  /// Applies a sequence of generated Permissioned Data operations.
  public mutating func apply<Operations: Sequence>(_ operations: Operations) throws
  where Operations.Element: PermissionedRepoOperationDescribing {
    for operation in operations {
      try apply(operation)
    }
  }

  /// Whether the local LtHash digest equals a signed commit's claimed hash.
  ///
  /// This comparison alone does not authenticate the claim. Prefer
  /// ``verify(_:context:publicKey:limits:)`` when the author key is available.
  public func matches(_ commit: any PermissionedRepoSignedCommitDescribing) -> Bool {
    setHash.digest == commit.permissionedRepoCommitHash
  }

  /// Authenticates a signed commit and compares it with this repository state.
  public func verify(
    _ commit: any PermissionedRepoSignedCommitDescribing,
    context: RepoCommitContext,
    publicKey: ATProtoCrypto.PublicKey,
    limits: RepoVerificationLimits = .init()
  ) throws {
    try SignedRepoCommitVerifier.verify(
      commit, context: context, publicKey: publicKey, limits: limits)
    guard matches(commit) else {
      throw RepoVerificationError.setHashMismatch
    }
  }

  private static func validatedLink(_ value: FormatString<LexLink>?) throws -> LexLink? {
    guard let value else { return nil }
    guard let link = value.typed else {
      throw RepoVerificationError.malformedOperation
    }
    return link
  }

  private static func element(for record: RepoRecord) -> String {
    "\(record.collection.rawValue)/\(record.recordKey.rawValue)/\(record.cid.toBaseEncodedString)"
  }
}

extension RepoRecord {
  init(path: String, cid: LexLink) throws {
    guard let separator = path.firstIndex(of: "/") else {
      throw RepoVerificationError.malformedRecordPath(path)
    }
    let collectionRaw = String(path[..<separator])
    let recordKeyRaw = String(path[path.index(after: separator)...])
    do {
      self = RepoRecord(
        collection: try NSID(string: collectionRaw),
        recordKey: try RecordKey(string: recordKeyRaw),
        cid: cid)
    } catch {
      throw RepoVerificationError.malformedRecordPath(path)
    }
  }
}
