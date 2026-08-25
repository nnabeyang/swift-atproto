import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository recovery")
struct RepoSyncTests {
  private let space = try! SpaceRef(
    string: "at://did:plc:spaceauthority/space/com.example.project/demo")
  private let author = try! SwiftAtproto.DID(string: "did:plc:alice")
  private let baseRevision = try! TID(string: "3kbgyjzqfeq2e")
  private let headRevision = try! TID(string: "3kbgyjzqfeq2f")
  private let key = try! PrivateKey(
    type: .ed25519, rawValue: Data(repeating: 9, count: 32))
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
    let context = headContext()
    let commit = try signedCommit(repository: repository, context: context)

    let result = try update.finish(
      commit, context: context, publicKey: key.publicKey)
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
    let checkpoint = try restoredCheckpoint(records: [first])
    let update = RepoIncrementalSync(checkpoint: checkpoint)
    let context = headContext()
    let commit = try signedCommit(
      repository: RepoCommit(records: [first, second]), context: context)

    #expect(
      try update.finish(commit, context: context, publicKey: key.publicKey)
        == .fullStateRecoveryRequired(.incrementalStateMismatch))
  }

  @Test("maps a divergent local state to the same recovery result")
  func requiresRecoveryForDivergentState() throws {
    let checkpoint = try restoredCheckpoint(records: [first])
    var update = RepoIncrementalSync(checkpoint: checkpoint)
    try update.apply([SyncStubOperation(record: second, previousCID: nil)])
    let context = headContext()
    let commit = try signedCommit(repository: RepoCommit(records: [first]), context: context)

    #expect(
      try update.finish(commit, context: context, publicKey: key.publicKey)
        == .fullStateRecoveryRequired(.incrementalStateMismatch))
  }

  @Test("does not classify an unauthenticated commit as recoverable")
  func rejectsUnauthenticatedCommit() throws {
    let checkpoint = try restoredCheckpoint(records: [first])
    let update = RepoIncrementalSync(checkpoint: checkpoint)
    let context = headContext()
    var commit = try signedCommit(repository: checkpoint.repository, context: context)
    commit.mac[0] ^= 0xff

    #expect(throws: RepoVerificationError.macMismatch) {
      try update.finish(commit, context: context, publicKey: key.publicKey)
    }
  }

  @Test("rejects a commit older than the durable checkpoint")
  func rejectsStaleCommit() throws {
    let checkpoint = try RepoSyncCheckpoint(
      revision: headRevision,
      state: RepoCommit(records: [first]).setHash.state)
    let update = RepoIncrementalSync(checkpoint: checkpoint)
    let context = RepoCommitContext(space: space, author: author, revision: baseRevision)
    let commit = try signedCommit(repository: checkpoint.repository, context: context)

    #expect(
      throws: RepoVerificationError.staleCommitRevision(
        checkpoint: headRevision, commit: baseRevision)
    ) {
      try update.finish(commit, context: context, publicKey: key.publicKey)
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

    let context = headContext()
    let commit = try signedCommit(repository: checkpoint.repository, context: context)
    #expect(
      try update.finish(commit, context: context, publicKey: key.publicKey)
        == .synchronized(
          RepoSyncCheckpoint(revision: headRevision, repository: checkpoint.repository)))
  }

  @Test("creates a replacement checkpoint from a verified full state")
  func createsFullStateCheckpoint() throws {
    let repository = RepoCommit(records: [first, second])
    let context = headContext()
    let commit = try signedCommit(repository: repository, context: context)

    let checkpoint = try repository.verifiedCheckpoint(
      commit, context: context, publicKey: key.publicKey)

    #expect(checkpoint.revision == headRevision)
    #expect(checkpoint.repository == repository)
    #expect(checkpoint.state == repository.setHash.state)
  }

  @Test("replaces a checkpoint after consuming a verified repository CAR")
  func replacesCheckpointFromCAR() async throws {
    let recordPayload = try CborEncoder(
      options: .lexicographicallySortedMapKeys
    ).encode(["text": "hello"])
    let recordCID = try carCID(for: recordPayload)
    let record = RepoRecord(
      collection: try NSID(string: "com.example.record"),
      recordKey: try RecordKey(string: "car"),
      cid: recordCID)
    let repository = RepoCommit(records: [record])
    let context = headContext()
    let commit = try signedCommit(repository: repository, context: context)
    let commitPayload = try CborEncoder(
      options: .lexicographicallySortedMapKeys
    ).encode(commit)
    let indexPayload = try CborEncoder(
      options: .lexicographicallySortedMapKeys,
      allowedTags: [42]
    ).encode(["com.example.record/car": recordCID])
    let commitCID = try carCID(for: commitPayload)
    let indexCID = try carCID(for: indexPayload)
    let carBytes =
      try carHeader(roots: [commitCID, indexCID])
      + carBlock(cid: commitCID, payload: commitPayload)
      + carBlock(cid: indexCID, payload: indexPayload)
      + carBlock(cid: recordCID, payload: recordPayload)

    let car = try await PermissionedRepoCAR.read(from: XRPCBody(carBytes))
    let decoded = try SignedRepoCommitVerifier.decode(
      SyncTestSignedCommit.self,
      fromDRISL: car.signedCommitBlock.bytes)
    try car.repository.verify(decoded, context: context, publicKey: key.publicKey)

    var records = car.recordBlocks.makeAsyncIterator()
    #expect(try await records.next()?.bytes == recordPayload)
    #expect(try await records.next() == nil)

    let replacement = try car.repository.verifiedCheckpoint(
      decoded, context: context, publicKey: key.publicKey)
    #expect(replacement.revision == headRevision)
    #expect(replacement.repository == repository)
  }

  private func restoredCheckpoint(records: [RepoRecord]) throws -> RepoSyncCheckpoint {
    try RepoSyncCheckpoint(
      revision: baseRevision,
      state: RepoCommit(records: records).setHash.state)
  }

  private func headContext() -> RepoCommitContext {
    RepoCommitContext(space: space, author: author, revision: headRevision)
  }

  private func signedCommit(
    repository: RepoCommit,
    context: RepoCommitContext
  ) throws -> SyncTestSignedCommit {
    let inputKeyMaterial = Data((0..<32).map(UInt8.init))
    let contextBytes = try context.encoded(inputKeyMaterial: inputKeyMaterial)
    let macKey = HKDF<SHA256>.expand(
      pseudoRandomKey: SymmetricKey(data: inputKeyMaterial),
      info: contextBytes,
      outputByteCount: 32)
    let hash = repository.setHash.digest
    return SyncTestSignedCommit(
      ver: 1,
      hash: hash,
      ikm: inputKeyMaterial,
      sig: try key.sign(contextBytes),
      mac: Data(HMAC<SHA256>.authenticationCode(for: hash, using: macKey)),
      rev: .init(rawValue: context.revision.rawValue))
  }

  private func carCID(for payload: Data) throws -> LexLink {
    try LexLink(
      Data([0x01, 0x71, 0x12, 0x20])
        + Data(SHA256.hash(data: payload)))
  }

  private func carHeader(roots: [LexLink]) throws -> Data {
    let payload = try CborEncoder(
      options: .lexicographicallySortedMapKeys,
      allowedTags: [42]
    ).encode(SyncCARHeader(roots: roots, version: 1))
    return unsignedVarint(UInt64(payload.count)) + payload
  }

  private func carBlock(cid: LexLink, payload: Data) -> Data {
    let cidBytes = Data(cid.cid.rawBuffer)
    return unsignedVarint(UInt64(cidBytes.count + payload.count)) + cidBytes + payload
  }

  private func unsignedVarint(_ input: UInt64) -> Data {
    var value = input
    var result = Data()
    repeat {
      var byte = UInt8(value & 0x7f)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      result.append(byte)
    } while value != 0
    return result
  }
}

private struct SyncTestSignedCommit: Codable, Hashable, PermissionedRepoSignedCommitDescribing {
  var ver: Int
  var hash: Data
  var ikm: Data
  var sig: Data
  var mac: Data
  var rev: FormatString<TID>

  var permissionedRepoCommitVersion: Int { ver }
  var permissionedRepoCommitHash: Data { hash }
  var permissionedRepoCommitInputKeyMaterial: Data { ikm }
  var permissionedRepoCommitSignature: Data { sig }
  var permissionedRepoCommitMAC: Data { mac }
  var permissionedRepoCommitRevision: FormatString<TID> { rev }
}

private struct SyncCARHeader: Encodable {
  let roots: [LexLink]
  let version: Int
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
