import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository STAR archives")
struct PermissionedRepoSTARTests {
  private let space = try! SpaceRef(
    string: "at://did:plc:spaceauthority/space/com.example.project/demo")
  private let author = try! SwiftAtproto.DID(string: "did:plc:alice")
  private let revision = try! TID(string: "3kbgyjzqfeq2f")

  @Test("reads, authenticates, and checkpoints a complete archive")
  func roundTrips() async throws {
    let records = try [
      ("com.example.post/a", Self.record("hello")),
      ("com.example.post/b", Self.record("world")),
      ("com.example.reply/a", Self.record("again")),
    ]
    let archive = try archive(records)

    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(archive.bytes), authentication: archive.authentication)
    #expect(star.revision == revision)
    #expect(star.commit.repo.rawValue == author.rawValue)
    #expect(throws: RepoVerificationError.incompleteRepository) { try star.verifiedCheckpoint() }

    var read: [PermissionedRepoSTARRecord] = []
    for try await record in star.records {
      read.append(record)
    }
    #expect(read.map { "\($0.collection.rawValue)/\($0.recordKey.rawValue)" } == records.map(\.0))
    #expect(read.map(\.bytes) == records.map(\.1))
    #expect(read[0].cid == (try Self.cid(records[0].1)))

    let checkpoint = try star.verifiedCheckpoint()
    #expect(checkpoint.revision == revision)
    #expect(checkpoint.repository == archive.repository)
  }

  @Test("reads an archive delivered in arbitrary chunks")
  func readsSplitChunks() async throws {
    let archive = try archive([("com.example.post/a", Self.record("hello"))])
    let chunks = archive.bytes.map { [$0] }
    let body = XRPCBody(
      AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
        for chunk in chunks { continuation.yield(ArraySlice(chunk)) }
        continuation.finish()
      })

    let star = try await PermissionedRepoSTAR.read(from: body, authentication: archive.authentication)
    var count = 0
    for try await _ in star.records { count += 1 }
    #expect(count == 1)
    #expect(try star.verifiedCheckpoint().repository == archive.repository)
  }

  @Test("an empty repo has no pairs")
  func readsAnEmptyRepo() async throws {
    let archive = try archive([])
    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(archive.bytes), authentication: archive.authentication)
    var iterator = star.records.makeAsyncIterator()
    #expect(try await iterator.next() == nil)
    #expect(try star.verifiedCheckpoint().repository == RepoCommit())
  }

  @Test("rejects a MAC that does not authenticate the metadata")
  func rejectsAWrongMAC() async throws {
    let archive = try archive([("com.example.post/a", Self.record("hello"))])
    await #expect(throws: RepoVerificationError.macMismatch) {
      _ = try await PermissionedRepoSTAR.read(
        from: XRPCBody(archive.bytes),
        authentication: archive.authentication.replacing(sharedSecret: SymmetricKey(size: .bits256)))
    }
    await #expect(throws: RepoVerificationError.commitIdentityMismatch) {
      _ = try await PermissionedRepoSTAR.read(
        from: XRPCBody(archive.bytes),
        authentication: archive.authentication.replacing(
          repo: try SwiftAtproto.DID(string: "did:plc:bob")))
    }
  }

  @Test("rejects records whose digest does not match the commit")
  func rejectsADigestMismatch() async throws {
    // The commit claims one record, the archive carries another.
    let archive = try archive(
      [("com.example.post/a", Self.record("world"))],
      claiming: [("com.example.post/a", Self.record("hello"))])
    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(archive.bytes), authentication: archive.authentication)
    var iterator = star.records.makeAsyncIterator()
    #expect(try await iterator.next() != nil)
    await #expect(throws: RepoVerificationError.setHashMismatch) {
      _ = try await iterator.next()
    }
    #expect(throws: RepoVerificationError.incompleteRepository) { try star.verifiedCheckpoint() }
  }

  @Test(
    "rejects out-of-order and duplicate paths",
    arguments: [
      ["com.example.post/b", "com.example.post/a"],
      ["com.example.post/a", "com.example.post/a"],
      // Bytewise order: "post" sorts before "post2", and "Z" before "a".
      ["com.example.post2/a", "com.example.post/a"],
      ["com.example.post/a", "com.example.post/Z"],
    ])
  func rejectsUnorderedPaths(paths: [String]) async throws {
    let archive = try archive(try paths.map { ($0, try Self.record($0)) })
    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(archive.bytes), authentication: archive.authentication)
    var iterator = star.records.makeAsyncIterator()
    _ = try await iterator.next()
    await #expect(throws: RepoVerificationError.recordOutOfOrder(paths[1])) {
      _ = try await iterator.next()
    }
  }

  @Test("rejects a record larger than the limit before reading it")
  func rejectsAnOversizedRecord() async throws {
    let value = try Self.record(String(repeating: "x", count: 64))
    let archive = try archive([("com.example.post/a", value)])
    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(archive.bytes), authentication: archive.authentication,
      limits: RepoVerificationLimits(maximumRecordBytes: value.count - 1))
    var iterator = star.records.makeAsyncIterator()
    await #expect(
      throws: RepoVerificationError.inputTooLarge(limit: value.count - 1, actual: value.count)
    ) {
      _ = try await iterator.next()
    }
  }

  @Test("rejects an archive that ends inside a pair or a frame")
  func rejectsTruncation() async throws {
    let archive = try archive([("com.example.post/a", Self.record("hello"))])
    let metadataEnd = archive.metadataEnd
    // Cut after the key, and inside the value.
    for cut in [archive.bytes.count - (try Self.record("hello")).count - 1, archive.bytes.count - 1] {
      let star = try await PermissionedRepoSTAR.read(
        from: XRPCBody(archive.bytes.prefix(cut)), authentication: archive.authentication)
      var iterator = star.records.makeAsyncIterator()
      await #expect(throws: RepoVerificationError.truncatedSTAR) {
        _ = try await iterator.next()
      }
    }
    // Cut inside the metadata.
    await #expect(throws: RepoVerificationError.truncatedSTAR) {
      _ = try await PermissionedRepoSTAR.read(
        from: XRPCBody(archive.bytes.prefix(metadataEnd - 1)), authentication: archive.authentication)
    }
  }

  @Test("rejects wrong magic, a non-minimal varint, and a non-map record")
  func rejectsMalformedFraming() async throws {
    let archive = try archive([])
    var magic = archive.bytes
    magic[1] = 0x6d
    await #expect(throws: RepoVerificationError.invalidSTARMagic) {
      _ = try await PermissionedRepoSTAR.read(from: XRPCBody(magic), authentication: archive.authentication)
    }

    // A one-byte key written as two varint bytes.
    let padded = archive.bytes + Data([0x81, 0x00, 0x61])
    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(padded), authentication: archive.authentication)
    var iterator = star.records.makeAsyncIterator()
    await #expect(throws: RepoVerificationError.malformedSTARVarint) {
      _ = try await iterator.next()
    }

    let list = try CborEncoder(options: .lexicographicallySortedMapKeys).encode(["hello"])
    let notMap = try self.archive([("com.example.post/a", list)])
    let listStar = try await PermissionedRepoSTAR.read(
      from: XRPCBody(notMap.bytes), authentication: notMap.authentication)
    var listIterator = listStar.records.makeAsyncIterator()
    await #expect(throws: RepoVerificationError.malformedRecord("com.example.post/a")) {
      _ = try await listIterator.next()
    }
  }

  @Test("rejects metadata of another profile or in non-canonical form")
  func rejectsMalformedMetadata() async throws {
    let archive = try archive([])
    let otherProfile = try Self.star(
      metadata: Self.metadata(type: "other-profile", commit: archive.commit), pairs: [])
    await #expect(throws: RepoVerificationError.malformedCommit) {
      _ = try await PermissionedRepoSTAR.read(
        from: XRPCBody(otherProfile), authentication: archive.authentication)
    }

    // The same map with its keys in the order they are declared, not sorted.
    let unsorted = try CborEncoder().encode(
      UnsortedMetadata(commit: archive.commit))
    await #expect(throws: RepoVerificationError.malformedCommit) {
      _ = try await PermissionedRepoSTAR.read(
        from: XRPCBody(try Self.star(metadata: unsorted, pairs: [])),
        authentication: archive.authentication)
    }
  }

  @Test("the record sequence can be consumed once")
  func refusesASecondIteration() async throws {
    let archive = try archive([])
    let star = try await PermissionedRepoSTAR.read(
      from: XRPCBody(archive.bytes), authentication: archive.authentication)
    _ = star.records.makeAsyncIterator()
    var second = star.records.makeAsyncIterator()
    await #expect(throws: RepoVerificationError.recordsAlreadyConsumed) {
      _ = try await second.next()
    }
  }

  // MARK: - Fixtures

  private struct Archive {
    let bytes: Data
    let metadataEnd: Int
    let commit: SyncTestCommit
    let repository: RepoCommit
    let authentication: RepoCommitAuthentication
  }

  private func archive(
    _ pairs: [(String, Data)], claiming claimed: [(String, Data)]? = nil
  ) throws -> Archive {
    let repository = try RepoCommit(
      records: (claimed ?? pairs).map { try RepoRecord(path: $0.0, cid: Self.cid($0.1)) })
    let commit = SyncTestCommit(repository: repository, space: space, repo: author, revision: revision)
    let metadata = try Self.metadata(type: "atproto-space-repo", commit: commit)
    return Archive(
      bytes: try Self.star(metadata: metadata, pairs: pairs),
      metadataEnd: PermissionedRepoSTAR.magic.count + Self.varint(metadata.count).count + metadata.count,
      commit: commit,
      repository: repository,
      authentication: try SyncTestResponse(commit: commit, space: space, repo: author).authentication)
  }

  private static func star(metadata: Data, pairs: [(String, Data)]) throws -> Data {
    var bytes = Data(PermissionedRepoSTAR.magic) + varint(metadata.count) + metadata
    for (key, value) in pairs {
      bytes += varint(key.utf8.count) + Data(key.utf8) + varint(value.count) + value
    }
    return bytes
  }

  private static func metadata(type: String, commit: SyncTestCommit) throws -> Data {
    try CborEncoder(options: .lexicographicallySortedMapKeys).encode(
      Metadata(type: type, commit: commit))
  }

  private static func record(_ text: String) throws -> Data {
    try CborEncoder(options: .lexicographicallySortedMapKeys).encode(["text": text])
  }

  private static func cid(_ bytes: Data) throws -> LexLink {
    try LexLink(Data([0x01, 0x71, 0x12, 0x20]) + Data(SHA256.hash(data: bytes)))
  }

  private static func varint(_ value: Int) -> Data {
    var value = UInt64(value)
    var result = Data()
    repeat {
      var byte = UInt8(value & 0x7f)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      result.append(byte)
    } while value != 0
    return result
  }

  private struct Metadata: Encodable {
    let type: String
    let commit: SyncTestCommit

    enum CodingKeys: String, CodingKey {
      case type = "$type"
      case ver, repo, space, rev, data
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(type, forKey: .type)
      try container.encode(commit.ver, forKey: .ver)
      try container.encode(commit.repo, forKey: .repo)
      try container.encode(commit.space, forKey: .space)
      try container.encode(commit.rev, forKey: .rev)
      try container.encode(commit.data, forKey: .data)
    }
  }

  private struct UnsortedMetadata: Encodable {
    let commit: SyncTestCommit

    enum CodingKeys: String, CodingKey {
      case type = "$type"
      case space, repo, ver, rev, data
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("atproto-space-repo", forKey: .type)
      try container.encode(commit.space, forKey: .space)
      try container.encode(commit.repo, forKey: .repo)
      try container.encode(commit.ver, forKey: .ver)
      try container.encode(commit.rev, forKey: .rev)
      try container.encode(commit.data, forKey: .data)
    }
  }
}
