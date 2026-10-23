import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository recovery")
struct RepoSyncTests {
  private let space = try! SpaceRef(
    string: "at://did:plc:spaceauthority/space/com.example.project/demo")
  private let author = try! SwiftAtproto.DID(string: "did:plc:alice")
  private let baseRevision = try! TID(string: "3kbgyjzqfeq2e")
  private let headRevision = try! TID(string: "3kbgyjzqfeq2f")
  private let first = RepoRecord(
    collection: try! NSID(string: "com.example.record"),
    recordKey: try! RecordKey(string: "first"),
    cid: try! LexLink("bafyreidefdycgbfy3oglcb6ism3eqhyp5llsrpzxjsuac2gsy4mtrtx244"))
  private let second = RepoRecord(
    collection: try! NSID(string: "com.example.record"),
    recordKey: try! RecordKey(string: "second"),
    cid: try! LexLink("bafyreidpw4cbv6gr4ukh33z23pvvrpr3wi4gnpmi4doamlsl3sa4rgri2a"))

  @Test("advances a durable checkpoint after incremental verification")
  func advancesCheckpoint() throws {
    let checkpoint = try restoredCheckpoint(records: [first])
    var update = RepoIncrementalSync(checkpoint: checkpoint)
    try update.apply([SyncStubOperation(record: second, previousCID: nil)])
    let repository = RepoCommit(records: [first, second])
    let (commit, authentication) = try headCommit(repository)

    let result = try update.finish(commit, authentication: authentication)
    let replacement: RepoSyncCheckpoint
    switch result {
    case .synchronized(let value):
      replacement = value
    case .fullStateRecoveryRequired:
      Issue.record("matching incremental state requested full recovery")
      return
    }

    #expect(replacement.revision == headRevision)
    #expect(replacement.repository == repository)
    #expect(try RepoSyncCheckpoint(revision: headRevision, state: replacement.state) == replacement)
    #expect(checkpoint.repository == RepoCommit(records: [first]))
  }

  @Test("maps missing history to full-state recovery")
  func requiresRecoveryForMissingHistory() throws {
    let update = RepoIncrementalSync(checkpoint: try restoredCheckpoint(records: [first]))
    let (commit, authentication) = try headCommit(RepoCommit(records: [first, second]))

    #expect(
      try update.finish(commit, authentication: authentication)
        == .fullStateRecoveryRequired(.incrementalStateMismatch))
  }

  @Test("maps a divergent local state to the same recovery result")
  func requiresRecoveryForDivergentState() throws {
    var update = RepoIncrementalSync(checkpoint: try restoredCheckpoint(records: [first]))
    try update.apply([SyncStubOperation(record: second, previousCID: nil)])
    let (commit, authentication) = try headCommit(RepoCommit(records: [first]))

    #expect(
      try update.finish(commit, authentication: authentication)
        == .fullStateRecoveryRequired(.incrementalStateMismatch))
  }

  @Test("does not classify an unauthenticated commit as recoverable")
  func rejectsUnauthenticatedCommit() throws {
    let checkpoint = try restoredCheckpoint(records: [first])
    let update = RepoIncrementalSync(checkpoint: checkpoint)
    let (commit, authentication) = try headCommit(checkpoint.repository)
    var mac = authentication.mac
    mac[0] ^= 0xff

    #expect(throws: RepoVerificationError.macMismatch) {
      try update.finish(commit, authentication: authentication.replacing(mac: mac))
    }
    #expect(throws: RepoVerificationError.macMismatch) {
      try update.finish(
        commit, authentication: authentication.replacing(sharedSecret: SymmetricKey(size: .bits256)))
    }
  }

  @Test("does not trust a commit whose data changed after the MAC")
  func rejectsAChangedClaim() throws {
    let checkpoint = try restoredCheckpoint(records: [first])
    let update = RepoIncrementalSync(checkpoint: checkpoint)
    var (commit, authentication) = try headCommit(RepoCommit(records: [first, second]))
    // A response whose data was replaced to match the candidate still fails.
    commit.data = checkpoint.repository.setHash.digest

    #expect(throws: RepoVerificationError.macMismatch) {
      try update.finish(commit, authentication: authentication)
    }
  }

  @Test("rejects a commit for another repo or space")
  func rejectsAnotherIdentity() throws {
    let update = RepoIncrementalSync(checkpoint: try restoredCheckpoint(records: [first]))
    let (commit, authentication) = try headCommit(RepoCommit(records: [first]))
    let otherSpace = try SpaceRef(string: "at://did:plc:spaceauthority/space/com.example.project/other")

    #expect(throws: RepoVerificationError.commitIdentityMismatch) {
      try update.finish(
        commit, authentication: authentication.replacing(repo: try SwiftAtproto.DID(string: "did:plc:bob")))
    }
    #expect(throws: RepoVerificationError.commitIdentityMismatch) {
      try update.finish(commit, authentication: authentication.replacing(space: otherSpace))
    }
  }

  @Test("rejects an unsupported version and malformed fields")
  func rejectsMalformedCommits() throws {
    let update = RepoIncrementalSync(checkpoint: try restoredCheckpoint(records: [first]))
    let (commit, authentication) = try headCommit(RepoCommit(records: [first]))

    var version = commit
    version.ver = 2
    #expect(throws: RepoVerificationError.unsupportedCommitVersion(2)) {
      try update.finish(version, authentication: authentication)
    }
    var data = commit
    data.data = Data(count: 31)
    #expect(throws: RepoVerificationError.invalidCommitField(field: "data")) {
      try update.finish(data, authentication: authentication)
    }
    var revision = commit
    revision.rev = .init(rawValue: "not-a-tid")
    #expect(throws: RepoVerificationError.invalidCommitField(field: "rev")) {
      try update.finish(revision, authentication: authentication)
    }
  }

  @Test("rejects a commit older than the durable checkpoint")
  func rejectsStaleCommit() throws {
    let checkpoint = try RepoSyncCheckpoint(
      revision: headRevision,
      state: RepoCommit(records: [first]).setHash.state)
    let update = RepoIncrementalSync(checkpoint: checkpoint)
    let (commit, authentication) = try headCommit(checkpoint.repository, revision: baseRevision)

    #expect(
      throws: RepoVerificationError.staleCommitRevision(
        checkpoint: headRevision, commit: baseRevision)
    ) {
      try update.finish(commit, authentication: authentication)
    }
  }

  @Test("applies each operation page transactionally")
  func rejectsAnEntireMalformedPage() throws {
    let checkpoint = try restoredCheckpoint(records: [first])
    var update = RepoIncrementalSync(checkpoint: checkpoint)
    let malformed = SyncStubOperation(
      collection: "not-an-nsid", recordKey: "bad", cid: nil, previousCID: nil)

    #expect(throws: RepoVerificationError.malformedOperation) {
      try update.apply([
        SyncStubOperation(record: second, previousCID: nil),
        malformed,
      ])
    }

    let (commit, authentication) = try headCommit(checkpoint.repository)
    #expect(
      try update.finish(commit, authentication: authentication)
        == .synchronized(
          RepoSyncCheckpoint(revision: headRevision, repository: checkpoint.repository)))
  }

  @Test("creates a replacement checkpoint from a verified full state")
  func createsFullStateCheckpoint() throws {
    let repository = RepoCommit(records: [first, second])
    let (commit, authentication) = try headCommit(repository)

    let checkpoint = try repository.verifiedCheckpoint(commit, authentication: authentication)

    #expect(checkpoint.revision == headRevision)
    #expect(checkpoint.repository == repository)
    #expect(checkpoint.state == repository.setHash.state)
    #expect(throws: RepoVerificationError.setHashMismatch) {
      try RepoCommit(records: [first]).verifiedCheckpoint(commit, authentication: authentication)
    }
  }

  private func restoredCheckpoint(records: [RepoRecord]) throws -> RepoSyncCheckpoint {
    try RepoSyncCheckpoint(
      revision: baseRevision,
      state: RepoCommit(records: records).setHash.state)
  }

  private func headCommit(
    _ repository: RepoCommit, revision: TID? = nil
  ) throws -> (SyncTestCommit, RepoCommitAuthentication) {
    let commit = SyncTestCommit(
      repository: repository, space: space, repo: author, revision: revision ?? headRevision)
    return (commit, try SyncTestResponse(commit: commit, space: space, repo: author).authentication)
  }
}

private struct SyncStubOperation: PermissionedRepoOperationDescribing {
  let permissionedRepoOperationCollection: FormatString<NSID>
  let permissionedRepoOperationRecordKey: FormatString<RecordKey>
  let permissionedRepoOperationCID: FormatString<LexLink>?
  let permissionedRepoOperationPreviousCID: FormatString<LexLink>?

  init(record: RepoRecord, previousCID: LexLink?) {
    self.init(
      collection: record.collection.rawValue,
      recordKey: record.recordKey.rawValue,
      cid: record.cid.toBaseEncodedString,
      previousCID: previousCID?.toBaseEncodedString)
  }

  init(collection: String, recordKey: String, cid: String?, previousCID: String?) {
    permissionedRepoOperationCollection = .init(rawValue: collection)
    permissionedRepoOperationRecordKey = .init(rawValue: recordKey)
    permissionedRepoOperationCID = cid.map(FormatString<LexLink>.init(rawValue:))
    permissionedRepoOperationPreviousCID = previousCID.map(
      FormatString<LexLink>.init(rawValue:))
  }
}
