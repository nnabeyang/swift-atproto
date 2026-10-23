import Foundation
import SwiftAtproto
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository state")
struct RepoCommitTests {
  private let first = RepoRecord(
    collection: try! NSID(string: "com.example.post"),
    recordKey: try! RecordKey(string: "first"),
    cid: try! LexLink("bafyreidefdycgbfy3oglcb6ism3eqhyp5llsrpzxjsuac2gsy4mtrtx244"))
  private let second = RepoRecord(
    collection: try! NSID(string: "com.example.post"),
    recordKey: try! RecordKey(string: "second"),
    cid: try! LexLink("bafyreidpw4cbv6gr4ukh33z23pvvrpr3wi4gnpmi4doamlsl3sa4rgri2a"))

  @Test func recordsAndOperationsConverge() throws {
    let records = RepoCommit(records: [first, second])

    var fromOperations = RepoCommit()
    try fromOperations.apply([
      StubOperation(record: first, previousCID: nil),
      StubOperation(record: second, previousCID: nil),
    ])

    #expect(records == fromOperations)
  }

  @Test func recordElementMatchesTheNodeReferenceVector() {
    let commit = RepoCommit(records: [first])
    #expect(
      commit.setHash.digest.hex == "fcc551a3fdab795be0e7640d11759201fc90a193295c11bb383245d6be16747f")
  }

  @Test func updateAndDeleteReplaceBothSidesOfAnOperation() throws {
    var commit = RepoCommit(records: [first])
    let replacement = try LexLink(
      "bafyreidpw4cbv6gr4ukh33z23pvvrpr3wi4gnpmi4doamlsl3sa4rgri2a")
    commit.apply(
      try RepoOperation(
        collection: first.collection,
        recordKey: first.recordKey,
        cid: replacement,
        previousCID: first.cid))
    #expect(
      commit
        == RepoCommit(
          records: [
            RepoRecord(
              collection: first.collection, recordKey: first.recordKey, cid: replacement)
          ]))

    commit.apply(
      try RepoOperation(
        collection: first.collection,
        recordKey: first.recordKey,
        cid: nil,
        previousCID: replacement))
    #expect(commit.setHash.isEmpty)
  }

  @Test func rejectsMalformedGeneratedOperation() {
    let malformed = StubOperation(
      collection: "not an nsid", recordKey: "first", cid: nil, previousCID: nil)
    var commit = RepoCommit()
    #expect(throws: RepoVerificationError.malformedOperation) {
      try commit.apply(malformed)
    }
  }
}

private struct StubOperation: PermissionedRepoOperationDescribing {
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
