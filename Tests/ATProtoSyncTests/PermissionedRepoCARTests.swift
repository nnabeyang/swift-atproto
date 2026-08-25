import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository CAR")
struct PermissionedRepoCARTests {
  @Test("reads roots eagerly and record blocks on demand")
  func readsWithBackpressure() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0xa1, 0x61, 0x61, 0x01])])
    let source = PullDrivenState(chunks: fixture.parts.map(ArraySlice.init))
    let body = XRPCBody(PullDrivenChunks(state: source), onCancel: { source.cancel() })

    let car = try await PermissionedRepoCAR.read(from: body)

    #expect(car.signedCommitBlock.bytes == fixture.commitPayload)
    #expect(car.repositoryIndexBlock.bytes == fixture.indexPayload)
    #expect(
      car.repository
        == RepoCommit(
          records: [
            RepoRecord(
              collection: try NSID(string: "com.example.record"),
              recordKey: try RecordKey(string: "first"),
              cid: try Fixture.cid(for: fixture.recordPayloads[0]))
          ]))
    #expect(source.snapshot == .init(pullCount: 3, isCancelled: false))

    var iterator = car.recordBlocks.makeAsyncIterator()
    let record = try #require(try await iterator.next())
    #expect(record.bytes == fixture.recordPayloads[0])
    #expect(record.collection.rawValue == "com.example.record")
    #expect(record.recordKey.rawValue == "first")
    #expect(record.cid == (try Fixture.cid(for: fixture.recordPayloads[0])))
    #expect(source.snapshot == .init(pullCount: 4, isCancelled: false))
    #expect(try await iterator.next() == nil)
  }

  @Test("accepts a repository without record blocks")
  func readsIndexOnlyCAR() async throws {
    let fixture = try Fixture(recordPayloads: [])
    let car = try await PermissionedRepoCAR.read(from: XRPCBody(fixture.data))
    var iterator = car.recordBlocks.makeAsyncIterator()
    #expect(try await iterator.next() == nil)
  }

  @Test("reads framing split at every byte boundary")
  func readsBytewiseChunks() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0xa0])])
    let chunks = fixture.data.map { ArraySlice([$0]) }
    let body = XRPCBody(PullDrivenChunks(state: PullDrivenState(chunks: chunks)))

    let car = try await PermissionedRepoCAR.read(from: body)
    var iterator = car.recordBlocks.makeAsyncIterator()

    #expect(try await iterator.next()?.bytes == fixture.recordPayloads[0])
    #expect(try await iterator.next() == nil)
  }

  @Test("rejects a second record-block iterator")
  func rejectsSecondConsumption() async throws {
    let fixture = try Fixture(recordPayloads: [])
    let car = try await PermissionedRepoCAR.read(from: XRPCBody(fixture.data))
    var first = car.recordBlocks.makeAsyncIterator()
    var second = car.recordBlocks.makeAsyncIterator()

    #expect(try await first.next() == nil)
    await #expect(throws: RepoVerificationError.carRecordBlocksAlreadyConsumed) {
      try await second.next()
    }
  }

  @Test("cancels an abandoned record stream")
  func cancelsRecordStream() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01])])
    let source = PullDrivenState(chunks: fixture.parts.map(ArraySlice.init))
    let body = XRPCBody(PullDrivenChunks(state: source), onCancel: { source.cancel() })
    let car = try await PermissionedRepoCAR.read(from: body)

    car.recordBlocks.cancel()

    #expect(source.snapshot.isCancelled)
  }

  @Test(
    "rejects malformed headers",
    arguments: [
      HeaderFailure.version,
      .rootCount,
      .malformed,
    ])
  func rejectsMalformedHeaders(_ failure: HeaderFailure) async throws {
    let fixture = try Fixture(recordPayloads: [])
    let body: Data
    let expected: RepoVerificationError
    switch failure {
    case .version:
      body = try Fixture.header(roots: fixture.roots, version: 2)
      expected = .unsupportedCARVersion(2)
    case .rootCount:
      body = try Fixture.header(roots: [fixture.roots[0]])
      expected = .invalidCARRootCount(actual: 1)
    case .malformed:
      body = Data([0x01, 0xff])
      expected = .malformedCARHeader
    }

    await #expect(throws: expected) {
      try await PermissionedRepoCAR.read(from: XRPCBody(body))
    }
  }

  @Test("rejects leading blocks that do not match root order")
  func rejectsRootOrderMismatch() async throws {
    let fixture = try Fixture(recordPayloads: [])
    let body = fixture.parts[0] + fixture.parts[2] + fixture.parts[1]

    await #expect(
      throws: RepoVerificationError.unexpectedCARRootBlock(
        expected: fixture.roots[0], actual: fixture.roots[1])
    ) {
      try await PermissionedRepoCAR.read(from: XRPCBody(body))
    }
  }

  @Test("rejects bytes that do not match a block CID")
  func rejectsCIDMismatch() async throws {
    let fixture = try Fixture(recordPayloads: [])
    let tamperedCommit = Fixture.block(
      cid: fixture.roots[0], payload: fixture.commitPayload + Data([0x00]))
    let body = fixture.parts[0] + tamperedCommit + fixture.parts[2]

    await #expect(throws: RepoVerificationError.carBlockCIDMismatch(fixture.roots[0])) {
      try await PermissionedRepoCAR.read(from: XRPCBody(body))
    }
  }

  @Test("rejects a record payload that does not match its CID")
  func rejectsRecordCIDMismatchLazily() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01])])
    let recordCID = try Fixture.cid(for: fixture.recordPayloads[0])
    let tamperedRecord = Fixture.block(cid: recordCID, payload: Data([0x02]))
    let body = fixture.parts.prefix(3).reduce(into: Data(), +=) + tamperedRecord
    let car = try await PermissionedRepoCAR.read(from: XRPCBody(body))
    var iterator = car.recordBlocks.makeAsyncIterator()

    await #expect(throws: RepoVerificationError.carBlockCIDMismatch(recordCID)) {
      try await iterator.next()
    }
  }

  @Test("rejects a record block not declared by an empty index")
  func rejectsExtraRecordBlock() async throws {
    let fixture = try Fixture(recordPayloads: [])
    let payload = Data([0xa0])
    let extraBlock = Fixture.block(cid: try Fixture.cid(for: payload), payload: payload)
    let car = try await PermissionedRepoCAR.read(
      from: XRPCBody(fixture.data + extraBlock))
    var iterator = car.recordBlocks.makeAsyncIterator()

    await #expect(throws: RepoVerificationError.unexpectedCARRecordBlock) {
      try await iterator.next()
    }
  }

  @Test("rejects a missing indexed record block")
  func rejectsMissingRecordBlock() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01]), Data([0x02])])
    let body = fixture.parts.dropLast().reduce(into: Data(), +=)
    let car = try await PermissionedRepoCAR.read(from: XRPCBody(body))
    var iterator = car.recordBlocks.makeAsyncIterator()

    #expect(try await iterator.next() != nil)
    await #expect(
      throws: RepoVerificationError.missingCARRecordBlocks(expected: 2, actual: 1)
    ) {
      try await iterator.next()
    }
  }

  @Test("rejects record blocks outside canonical index order")
  func rejectsRecordBlockOrderMismatch() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01]), Data([0x02])])
    let body =
      fixture.parts.prefix(3).reduce(into: Data(), +=)
      + fixture.parts[4] + fixture.parts[3]
    let car = try await PermissionedRepoCAR.read(from: XRPCBody(body))
    var iterator = car.recordBlocks.makeAsyncIterator()
    let expected = try Fixture.cid(for: fixture.recordPayloads[0])
    let actual = try Fixture.cid(for: fixture.recordPayloads[1])

    await #expect(
      throws: RepoVerificationError.unexpectedCARRecordCID(
        collection: try NSID(string: "com.example.record"),
        recordKey: try RecordKey(string: "first"),
        expected: expected,
        actual: actual)
    ) {
      try await iterator.next()
    }
  }

  @Test("rejects a self-consistent block with a CID absent from the index")
  func rejectsRecordCIDOutsideIndex() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01])])
    let replacementPayload = Data([0x02])
    let replacementCID = try Fixture.cid(for: replacementPayload)
    let body =
      fixture.parts.prefix(3).reduce(into: Data(), +=)
      + Fixture.block(cid: replacementCID, payload: replacementPayload)
    let car = try await PermissionedRepoCAR.read(from: XRPCBody(body))
    var iterator = car.recordBlocks.makeAsyncIterator()

    await #expect(
      throws: RepoVerificationError.unexpectedCARRecordCID(
        collection: try NSID(string: "com.example.record"),
        recordKey: try RecordKey(string: "first"),
        expected: try Fixture.cid(for: fixture.recordPayloads[0]),
        actual: replacementCID)
    ) {
      try await iterator.next()
    }
  }

  @Test("accepts index-only CARs only when record values are excluded")
  func distinguishesExcludedRecordValues() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01])])
    let indexOnly = fixture.parts.prefix(3).reduce(into: Data(), +=)
    let excluded = try await PermissionedRepoCAR.read(
      from: XRPCBody(indexOnly),
      recordValues: .excluded)
    var excludedIterator = excluded.recordBlocks.makeAsyncIterator()
    #expect(try await excludedIterator.next() == nil)

    let included = try await PermissionedRepoCAR.read(from: XRPCBody(indexOnly))
    var includedIterator = included.recordBlocks.makeAsyncIterator()
    await #expect(
      throws: RepoVerificationError.missingCARRecordBlocks(expected: 1, actual: 0)
    ) {
      try await includedIterator.next()
    }

    let valuesPresent = try await PermissionedRepoCAR.read(
      from: XRPCBody(fixture.data),
      recordValues: .excluded)
    var valuesPresentIterator = valuesPresent.recordBlocks.makeAsyncIterator()
    await #expect(throws: RepoVerificationError.unexpectedCARRecordBlock) {
      try await valuesPresentIterator.next()
    }
  }

  @Test(
    "rejects malformed or truncated framing",
    arguments: [
      FramingFailure.nonCanonicalVarint,
      .overflowingVarint,
      .truncatedVarint,
      .shortCID,
      .invalidCID,
      .truncatedPayload,
    ])
  func rejectsMalformedFraming(_ failure: FramingFailure) async throws {
    let fixture = try Fixture(recordPayloads: [])
    let body: Data
    let expected: RepoVerificationError
    switch failure {
    case .nonCanonicalVarint:
      body = Data([0x80, 0x00])
      expected = .malformedCARVarint
    case .overflowingVarint:
      body = Data(repeating: 0xff, count: 10) + Data([0x00])
      expected = .malformedCARVarint
    case .truncatedVarint:
      body = Data([0x80])
      expected = .truncatedCAR
    case .shortCID:
      body = fixture.parts[0] + Data([0x01, 0x00])
      expected = .malformedCARCID
    case .invalidCID:
      var invalidBlock = fixture.parts[1]
      invalidBlock[invalidBlock.startIndex + 1] = 0x02
      body = fixture.parts[0] + invalidBlock
      expected = .malformedCARCID
    case .truncatedPayload:
      let section = fixture.parts[1]
      body = fixture.parts[0] + section.dropLast()
      expected = .truncatedCAR
    }

    await #expect(throws: expected) {
      try await PermissionedRepoCAR.read(from: XRPCBody(body))
    }
  }

  @Test("enforces header and block limits before allocation")
  func enforcesLimits() async throws {
    let fixture = try Fixture(recordPayloads: [Data([0x01, 0x02])])
    let headerLength = fixture.parts[0].count - Fixture.varintLength(fixture.parts[0])
    await #expect(
      throws: RepoVerificationError.inputTooLarge(
        limit: headerLength - 1, actual: headerLength)
    ) {
      try await PermissionedRepoCAR.read(
        from: XRPCBody(fixture.data),
        limits: RepoVerificationLimits(maximumCARHeaderBytes: headerLength - 1))
    }

    await #expect(
      throws: RepoVerificationError.inputTooLarge(
        limit: fixture.commitPayload.count - 1, actual: fixture.commitPayload.count)
    ) {
      try await PermissionedRepoCAR.read(
        from: XRPCBody(fixture.data),
        limits: RepoVerificationLimits(
          maximumCommitBytes: fixture.commitPayload.count - 1))
    }

    await #expect(
      throws: RepoVerificationError.inputTooLarge(
        limit: fixture.indexPayload.count - 1, actual: fixture.indexPayload.count)
    ) {
      try await PermissionedRepoCAR.read(
        from: XRPCBody(fixture.data),
        limits: RepoVerificationLimits(
          maximumIndexBytes: fixture.indexPayload.count - 1))
    }

    let car = try await PermissionedRepoCAR.read(
      from: XRPCBody(fixture.data),
      limits: RepoVerificationLimits(maximumCARBlockBytes: 1))
    var iterator = car.recordBlocks.makeAsyncIterator()
    await #expect(throws: RepoVerificationError.inputTooLarge(limit: 1, actual: 2)) {
      try await iterator.next()
    }
  }
}

enum HeaderFailure: Sendable {
  case version
  case rootCount
  case malformed
}

enum FramingFailure: Sendable {
  case nonCanonicalVarint
  case overflowingVarint
  case truncatedVarint
  case shortCID
  case invalidCID
  case truncatedPayload
}

private struct Fixture {
  let commitPayload = Data([0xa1, 0x63, 0x76, 0x65, 0x72, 0x01])
  let indexPayload: Data
  let recordPayloads: [Data]
  let roots: [LexLink]
  let parts: [Data]

  var data: Data { parts.reduce(into: Data(), +=) }

  init(recordPayloads: [Data]) throws {
    self.recordPayloads = recordPayloads
    let recordEntries = try recordPayloads.enumerated().map { index, payload in
      (
        path: "com.example.record/\(Self.recordKey(at: index))",
        cid: try Self.cid(for: payload),
        payload: payload
      )
    }.sorted { lhs, rhs in
      let lhsBytes = Array(lhs.path.utf8)
      let rhsBytes = Array(rhs.path.utf8)
      if lhsBytes.count != rhsBytes.count { return lhsBytes.count < rhsBytes.count }
      return lhsBytes.lexicographicallyPrecedes(rhsBytes)
    }
    let index = Dictionary(uniqueKeysWithValues: recordEntries.map { ($0.path, $0.cid) })
    self.indexPayload = try CborEncoder(
      options: .lexicographicallySortedMapKeys,
      allowedTags: [42]
    ).encode(index)
    let commitCID = try Self.cid(for: commitPayload)
    let indexCID = try Self.cid(for: indexPayload)
    self.roots = [commitCID, indexCID]
    var parts = [
      try Self.header(roots: [commitCID, indexCID]),
      Self.block(cid: commitCID, payload: commitPayload),
      Self.block(cid: indexCID, payload: indexPayload),
    ]
    for entry in recordEntries {
      parts.append(Self.block(cid: entry.cid, payload: entry.payload))
    }
    self.parts = parts
  }

  private static func recordKey(at index: Int) -> String {
    switch index {
    case 0: "first"
    case 1: "second"
    case 2: "third"
    default: "record-\(index)"
    }
  }

  static func header(roots: [LexLink], version: Int = 1) throws -> Data {
    let bytes = try CborEncoder(
      options: .lexicographicallySortedMapKeys,
      allowedTags: [42]
    ).encode(Header(roots: roots, version: version))
    return varint(UInt64(bytes.count)) + bytes
  }

  static func block(cid: LexLink, payload: Data) -> Data {
    let cidBytes = Data(cid.cid.rawBuffer)
    return varint(UInt64(cidBytes.count + payload.count)) + cidBytes + payload
  }

  static func cid(for payload: Data) throws -> LexLink {
    try Data([0x01, 0x71, 0x12, 0x20])
      .appending(Data(SHA256.hash(data: payload)))
      .withUnsafeBytes { try LexLink(Data($0)) }
  }

  static func varint(_ value: UInt64) -> Data {
    var value = value
    var result = Data()
    repeat {
      var byte = UInt8(value & 0x7f)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      result.append(byte)
    } while value != 0
    return result
  }

  static func varintLength(_ data: Data) -> Int {
    data.prefix { $0 & 0x80 != 0 }.count + 1
  }

  private struct Header: Encodable {
    let roots: [LexLink]
    let version: Int
  }
}

private struct PullDrivenChunks: AsyncSequence, Sendable {
  typealias Element = ArraySlice<UInt8>

  let state: PullDrivenState

  func makeAsyncIterator() -> Iterator {
    Iterator(state: state)
  }

  struct Iterator: AsyncIteratorProtocol {
    let state: PullDrivenState

    mutating func next() async throws -> Element? {
      state.next()
    }
  }
}

private final class PullDrivenState: @unchecked Sendable {
  struct Snapshot: Equatable {
    let pullCount: Int
    let isCancelled: Bool
  }

  private let lock = NSLock()
  private let chunks: [ArraySlice<UInt8>]
  private var index = 0
  private var pullCount = 0
  private var isCancelled = false

  init(chunks: [ArraySlice<UInt8>]) {
    self.chunks = chunks
  }

  var snapshot: Snapshot {
    lock.withLock { Snapshot(pullCount: pullCount, isCancelled: isCancelled) }
  }

  func next() -> ArraySlice<UInt8>? {
    lock.withLock {
      guard index < chunks.count else { return nil }
      defer {
        index += 1
        pullCount += 1
      }
      return chunks[index]
    }
  }

  func cancel() {
    lock.withLock { isCancelled = true }
  }
}

extension Data {
  fileprivate func appending(_ other: Data) -> Data {
    var copy = self
    copy.append(other)
    return copy
  }
}
