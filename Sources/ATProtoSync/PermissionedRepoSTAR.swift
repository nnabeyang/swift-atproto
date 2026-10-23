import Crypto
import Foundation
import SwiftAtproto

/// The commit in the metadata of a repository STAR archive: the repo's
/// `com.atproto.space.defs#commit` plus the profile's `$type`.
public struct PermissionedRepoSTARCommit: Hashable, Sendable, Decodable,
  PermissionedRepoCommitDescribing
{
  /// The profile of a Permissioned Data repository archive.
  public static let type = "atproto-space-repo"

  /// The commit format version.
  public let ver: Int
  /// The DID of the repo's author.
  public let repo: FormatString<SwiftAtproto.DID>
  /// The space the repo belongs to.
  public let space: FormatString<SpaceRef>
  /// The commit revision.
  public let rev: FormatString<TID>
  /// The SHA-256 digest of the repository's LtHash state.
  public let data: Data

  public var permissionedRepoCommitVersion: Int { ver }
  public var permissionedRepoCommitRepo: FormatString<SwiftAtproto.DID> { repo }
  public var permissionedRepoCommitSpace: FormatString<SpaceRef> { space }
  public var permissionedRepoCommitRevision: FormatString<TID> { rev }
  public var permissionedRepoCommitData: Data { data }

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
    case ver, repo, space, rev, data
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .type) == Self.type else {
      throw RepoVerificationError.malformedCommit
    }
    ver = try container.decode(Int.self, forKey: .ver)
    repo = try container.decode(FormatString<SwiftAtproto.DID>.self, forKey: .repo)
    space = try container.decode(FormatString<SpaceRef>.self, forKey: .space)
    rev = try container.decode(FormatString<TID>.self, forKey: .rev)
    data = try container.decode(Data.self, forKey: .data)
  }
}

/// A record read from a repository STAR archive, with the CID computed from its
/// bytes.
public struct PermissionedRepoSTARRecord: Hashable, Sendable {
  /// The collection containing the record.
  public let collection: NSID

  /// The record key within ``collection``.
  public let recordKey: RecordKey

  /// The DAG-CBOR CID of ``bytes``.
  public let cid: LexLink

  /// The record's DRISL encoding.
  public let bytes: Data
}

/// A Permissioned Data repository read from a `getRepo` STAR-lite v1 archive
/// of the `atproto-space-repo` profile.
///
/// ```
/// [ magic | len | metadata ] [ len | path | len | record ] ...
/// ```
///
/// The metadata commit is checked against the response MAC before ``read(from:authentication:limits:)``
/// returns. Records stay pull-driven: each is folded into a running set hash
/// as ``records`` is consumed, and only when the archive ends with that hash
/// equal to the commit's `data` has the complete repo been received. Until
/// then nothing read from it is trustworthy, so stage records and persist them
/// with ``verifiedCheckpoint()`` only after the sequence reaches its `nil`.
///
/// See the [STAR specification](https://tangled.org/microcosm.blue/star/tree/main/v1-star).
public struct PermissionedRepoSTAR: Sendable {
  /// The STAR-lite v1 magic bytes.
  public static let magic: [UInt8] = [0x2a, 0x6c, 0x01, 0x00]

  /// The MAC-authenticated commit from the archive's metadata.
  public let commit: PermissionedRepoSTARCommit

  /// The authenticated commit's revision.
  public let revision: TID

  /// The remaining records, in strict path order.
  public let records: Records

  /// Reads the magic and metadata from an XRPC response body and
  /// authenticates the commit.
  ///
  /// Records are not pulled until ``records`` is consumed. Call
  /// ``Records/cancel()`` when abandoning the archive before reaching its end.
  public static func read(
    from body: XRPCBody,
    authentication: RepoCommitAuthentication,
    limits: RepoVerificationLimits = .init()
  ) async throws -> Self {
    let reader = STARReader(body: body)
    do {
      guard try await reader.readExactly(magic.count) == Data(magic) else {
        throw RepoVerificationError.invalidSTARMagic
      }
      guard let metadata = try await reader.readFrame(maximumBytes: limits.maximumCommitBytes)
      else {
        throw RepoVerificationError.truncatedSTAR
      }
      let commit: PermissionedRepoSTARCommit
      do {
        commit = try drislDecoder(
          maximumNestingDepth: 2,
          maximumContainerElements: 8,
          maximumStringBytes: limits.maximumCommitBytes
        ).decode(PermissionedRepoSTARCommit.self, from: metadata)
      } catch {
        throw RepoVerificationError.malformedCommit
      }
      let revision = try RepoCommitVerifier.verify(commit, authentication: authentication)
      return Self(
        commit: commit,
        revision: revision,
        records: Records(reader: reader, commit: commit, revision: revision, limits: limits))
    } catch {
      body.cancel()
      throw error
    }
  }

  /// The checkpoint of the complete repository.
  ///
  /// - Throws: ``RepoVerificationError/incompleteRepository`` until ``records``
  ///   has been consumed through its `nil` terminator without an error.
  public func verifiedCheckpoint() throws -> RepoSyncCheckpoint {
    guard let checkpoint = records.state.checkpoint else {
      throw RepoVerificationError.incompleteRepository
    }
    return checkpoint
  }

  /// A single-pass, pull-driven sequence of the archive's records.
  public final class Records: AsyncSequence, @unchecked Sendable {
    public typealias Element = PermissionedRepoSTARRecord

    private let reader: STARReader
    private let commit: PermissionedRepoSTARCommit
    private let revision: TID
    private let limits: RepoVerificationLimits
    fileprivate let state = ConsumptionState()

    fileprivate init(
      reader: STARReader, commit: PermissionedRepoSTARCommit, revision: TID,
      limits: RepoVerificationLimits
    ) {
      self.reader = reader
      self.commit = commit
      self.revision = revision
      self.limits = limits
    }

    /// Creates the sequence's single iterator.
    public func makeAsyncIterator() -> Iterator {
      guard state.beginIteration() else {
        return Iterator(throwing: RepoVerificationError.recordsAlreadyConsumed)
      }
      return Iterator(records: self)
    }

    /// Cancels the transport operation backing the archive.
    public func cancel() {
      reader.cancel()
    }

    /// The iterator that reads and checks one record per pull.
    public struct Iterator: AsyncIteratorProtocol {
      private let records: Records?
      private let error: (any Error)?
      private var repository = RepoCommit()
      private var previousPath: [UInt8]?
      private var count = 0
      private var finished = false

      fileprivate init(records: Records) {
        self.records = records
        self.error = nil
      }

      fileprivate init(throwing error: any Error) {
        self.records = nil
        self.error = error
      }

      public mutating func next() async throws -> PermissionedRepoSTARRecord? {
        if let error { throw error }
        guard let records, !finished else { return nil }
        do {
          guard
            let key = try await records.reader.readFrame(
              maximumBytes: records.limits.maximumRecordPathBytes)
          else {
            // EOF at a pair boundary ends the archive.
            finished = true
            guard repository.matches(records.commit) else {
              throw RepoVerificationError.setHashMismatch
            }
            records.state.finish(
              RepoSyncCheckpoint(revision: records.revision, repository: repository))
            return nil
          }
          let path = String(decoding: key, as: UTF8.self)
          let keyBytes = [UInt8](key)
          // Strictly increasing bytes: a repeat is a duplicate, a decrease out of order.
          if let previousPath, !previousPath.lexicographicallyPrecedes(keyBytes) {
            throw RepoVerificationError.recordOutOfOrder(path)
          }
          previousPath = keyBytes
          count += 1
          guard count <= records.limits.maximumRecords else {
            throw RepoVerificationError.inputTooLarge(
              limit: records.limits.maximumRecords, actual: count)
          }
          guard
            let value = try await records.reader.readFrame(
              maximumBytes: records.limits.maximumRecordBytes)
          else {
            throw RepoVerificationError.truncatedSTAR
          }
          do {
            _ = try drislDecoder(
              maximumNestingDepth: records.limits.maximumNestingDepth,
              maximumContainerElements: records.limits.maximumRecordBytes,
              maximumStringBytes: records.limits.maximumRecordBytes
            ).decode(RecordMap.self, from: value)
          } catch {
            throw RepoVerificationError.malformedRecord(path)
          }
          let cid = try LexLink(
            Data([0x01, 0x71, 0x12, 0x20]) + Data(SHA256.hash(data: value)))
          let reference = try RepoRecord(path: path, cid: cid)
          repository.add(reference)
          return PermissionedRepoSTARRecord(
            collection: reference.collection, recordKey: reference.recordKey, cid: cid,
            bytes: value)
        } catch {
          finished = true
          records.reader.cancel()
          throw error
        }
      }
    }
  }
}

/// Accepts any DRISL map. Decoding scans the whole value, so a record that is
/// not canonical DRISL is rejected along with one that is not a map.
private struct RecordMap: Decodable {
  init(from decoder: any Decoder) throws {
    _ = try decoder.container(keyedBy: AnyCodingKeys.self)
  }
}

private final class STARReader: @unchecked Sendable {
  private let body: XRPCBody
  private var iterator: XRPCBody.Iterator
  private var buffered: ArraySlice<UInt8> = []

  init(body: XRPCBody) {
    self.body = body
    self.iterator = body.makeAsyncIterator()
  }

  func cancel() {
    body.cancel()
  }

  /// One length-prefixed frame, or `nil` at EOF before the frame starts.
  func readFrame(maximumBytes: Int) async throws -> Data? {
    guard let length = try await readUnsignedVarint() else { return nil }
    guard length <= UInt64(max(maximumBytes, 0)) else {
      throw RepoVerificationError.inputTooLarge(
        limit: maximumBytes, actual: Int(exactly: length) ?? Int.max)
    }
    return try await readExactly(Int(length))
  }

  // Unsigned varint: 7 bits per byte, least significant group first, in its
  // shortest form. Frame limits keep lengths far below 2^63.
  private func readUnsignedVarint() async throws -> UInt64? {
    var value: UInt64 = 0
    for byteCount in 0..<9 {
      guard let byte = try await readByte() else {
        if byteCount == 0 { return nil }
        throw RepoVerificationError.truncatedSTAR
      }
      value |= UInt64(byte & 0x7f) << UInt64(byteCount * 7)
      if byte & 0x80 == 0 {
        // A final zero byte only pads the encoding, which STAR forbids.
        if byteCount > 0, byte == 0 {
          throw RepoVerificationError.malformedSTARVarint
        }
        return value
      }
    }
    throw RepoVerificationError.malformedSTARVarint
  }

  private func readByte() async throws -> UInt8? {
    while buffered.isEmpty {
      guard let chunk = try await iterator.next() else { return nil }
      buffered = chunk
    }
    return buffered.removeFirst()
  }

  func readExactly(_ count: Int) async throws -> Data {
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      while buffered.isEmpty {
        guard let chunk = try await iterator.next() else {
          throw RepoVerificationError.truncatedSTAR
        }
        buffered = chunk
      }
      let consumed = min(count - result.count, buffered.count)
      result.append(contentsOf: buffered.prefix(consumed))
      buffered = buffered.dropFirst(consumed)
    }
    return result
  }
}

private final class ConsumptionState: @unchecked Sendable {
  private let lock = NSLock()
  private var iterationStarted = false
  private var completed: RepoSyncCheckpoint?

  func beginIteration() -> Bool {
    lock.withLock {
      guard !iterationStarted else { return false }
      iterationStarted = true
      return true
    }
  }

  func finish(_ checkpoint: RepoSyncCheckpoint) {
    lock.withLock { completed = checkpoint }
  }

  var checkpoint: RepoSyncCheckpoint? {
    lock.withLock { completed }
  }
}
