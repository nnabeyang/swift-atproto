import Crypto
import Foundation
import SwiftAtproto

/// A verified block read from a Permissioned Data repository CAR.
public struct PermissionedRepoCARBlock: Hashable, Sendable {
  /// The DAG-CBOR CID that identifies ``bytes``.
  public let cid: LexLink

  /// The encoded DAG-CBOR block payload.
  public let bytes: Data

  init(cid: LexLink, bytes: Data) {
    self.cid = cid
    self.bytes = bytes
  }
}

/// A CID-verified record value paired with its repository-index path.
public struct PermissionedRepoCARRecord: Hashable, Sendable {
  /// The collection containing the record.
  public let collection: NSID

  /// The record key within ``collection``.
  public let recordKey: RecordKey

  /// The CID declared by the repository index.
  public let cid: LexLink

  /// The encoded DAG-CBOR record value.
  public let bytes: Data
}

/// The structurally verified, streaming contents of a Permissioned Data repository CAR.
///
/// Permissioned repository archives declare exactly two roots. The signed
/// commit and repository index blocks are read and checked eagerly, while
/// record blocks remain pull-driven through ``recordBlocks``.
public struct PermissionedRepoCAR: Sendable {
  /// Whether the CAR is expected to contain record value blocks.
  public enum RecordValues: Hashable, Sendable {
    /// A normal `getRepo` response containing one block per index entry.
    case included

    /// An `excludeValues: true` response containing only commit and index blocks.
    case excluded
  }

  /// The block matching the CAR's first, signed-commit root.
  public let signedCommitBlock: PermissionedRepoCARBlock

  /// The block matching the CAR's second, repository-index root.
  public let repositoryIndexBlock: PermissionedRepoCARBlock

  /// The complete repository state reconstructed from the index entries.
  ///
  /// Authenticate this state against the decoded signed commit before treating
  /// its paths and CIDs as an author claim.
  public let repository: RepoCommit

  /// The remaining CID-verified record blocks.
  public let recordBlocks: RecordBlocks

  /// Reads the CAR header and its two root blocks from an XRPC response body.
  ///
  /// Record blocks are not pulled until ``recordBlocks`` is consumed. Call
  /// ``RecordBlocks/cancel()`` when abandoning the archive before reaching its
  /// end.
  public static func read(
    from body: XRPCBody,
    recordValues: RecordValues = .included,
    limits: RepoVerificationLimits = .init()
  ) async throws -> Self {
    let reader = PermissionedRepoCARReader(body: body)
    do {
      let roots = try await reader.readRoots(limits: limits)
      let signedCommit = try await reader.requiredBlock(
        maximumPayloadBytes: limits.maximumCommitBytes)
      guard signedCommit.cid == roots[0] else {
        throw RepoVerificationError.unexpectedCARRootBlock(
          expected: roots[0], actual: signedCommit.cid)
      }

      let repositoryIndex = try await reader.requiredBlock(
        maximumPayloadBytes: limits.maximumIndexBytes)
      guard repositoryIndex.cid == roots[1] else {
        throw RepoVerificationError.unexpectedCARRootBlock(
          expected: roots[1], actual: repositoryIndex.cid)
      }
      let index = try PermissionedRepoIndex(
        drisl: repositoryIndex.bytes,
        limits: limits)

      return Self(
        signedCommitBlock: signedCommit,
        repositoryIndexBlock: repositoryIndex,
        repository: RepoCommit(records: index.records),
        recordBlocks: RecordBlocks(
          reader: reader,
          records: index.records,
          recordValues: recordValues,
          maximumPayloadBytes: limits.maximumCARBlockBytes))
    } catch {
      body.cancel()
      throw error
    }
  }

  /// A single-pass, pull-driven sequence of index-matched record blocks.
  ///
  /// Consume the sequence through its `nil` terminator to verify that the CAR
  /// contains neither missing nor extra record blocks.
  public final class RecordBlocks: AsyncSequence, @unchecked Sendable {
    public typealias Element = PermissionedRepoCARRecord

    private let reader: PermissionedRepoCARReader
    private let records: [RepoRecord]
    private let recordValues: RecordValues
    private let maximumPayloadBytes: Int
    private let state = ConsumptionState()

    fileprivate init(
      reader: PermissionedRepoCARReader,
      records: [RepoRecord],
      recordValues: RecordValues,
      maximumPayloadBytes: Int
    ) {
      self.reader = reader
      self.records = records
      self.recordValues = recordValues
      self.maximumPayloadBytes = maximumPayloadBytes
    }

    /// Creates the sequence's single iterator.
    public func makeAsyncIterator() -> Iterator {
      guard state.beginIteration() else {
        return Iterator(throwing: RepoVerificationError.carRecordBlocksAlreadyConsumed)
      }
      return Iterator(
        reader: reader,
        records: records,
        recordValues: recordValues,
        maximumPayloadBytes: maximumPayloadBytes)
    }

    /// Cancels the transport operation backing the CAR body.
    public func cancel() {
      reader.cancel()
    }

    /// The iterator that verifies one record block per pull.
    public struct Iterator: AsyncIteratorProtocol {
      private let reader: PermissionedRepoCARReader?
      private let records: [RepoRecord]
      private let recordValues: RecordValues
      private let maximumPayloadBytes: Int
      private let error: (any Error)?
      private var recordIndex = 0

      fileprivate init(
        reader: PermissionedRepoCARReader,
        records: [RepoRecord],
        recordValues: RecordValues,
        maximumPayloadBytes: Int
      ) {
        self.reader = reader
        self.records = records
        self.recordValues = recordValues
        self.maximumPayloadBytes = maximumPayloadBytes
        self.error = nil
      }

      fileprivate init(throwing error: any Error) {
        self.reader = nil
        self.records = []
        self.recordValues = .included
        self.maximumPayloadBytes = 0
        self.error = error
      }

      public mutating func next() async throws -> PermissionedRepoCARRecord? {
        if let error { throw error }
        guard let reader else { return nil }
        do {
          if recordValues == .excluded || recordIndex == records.count {
            guard
              try await reader.readBlock(maximumPayloadBytes: maximumPayloadBytes) == nil
            else {
              throw RepoVerificationError.unexpectedCARRecordBlock
            }
            return nil
          }

          guard
            let block = try await reader.readBlock(
              maximumPayloadBytes: maximumPayloadBytes)
          else {
            throw RepoVerificationError.missingCARRecordBlocks(
              expected: records.count,
              actual: recordIndex)
          }
          let record = records[recordIndex]
          guard block.cid == record.cid else {
            throw RepoVerificationError.unexpectedCARRecordCID(
              collection: record.collection,
              recordKey: record.recordKey,
              expected: record.cid,
              actual: block.cid)
          }
          recordIndex += 1
          return PermissionedRepoCARRecord(
            collection: record.collection,
            recordKey: record.recordKey,
            cid: record.cid,
            bytes: block.bytes)
        } catch {
          reader.cancel()
          throw error
        }
      }
    }
  }
}

private final class PermissionedRepoCARReader: @unchecked Sendable {
  private static let cidLength = 36
  private static let cidPrefix: [UInt8] = [0x01, 0x71, 0x12, 0x20]

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

  func readRoots(limits: RepoVerificationLimits) async throws -> [LexLink] {
    guard let encodedLength = try await readUnsignedVarint() else {
      throw RepoVerificationError.malformedCARHeader
    }
    guard
      limits.maximumCARHeaderBytes >= 0,
      encodedLength <= UInt64(limits.maximumCARHeaderBytes)
    else {
      throw RepoVerificationError.inputTooLarge(
        limit: limits.maximumCARHeaderBytes,
        actual: Int(exactly: encodedLength) ?? Int.max)
    }

    let headerBytes = try await readExactly(Int(encodedLength))
    let header: Header
    do {
      header = try drislDecoder(
        maximumNestingDepth: 4,
        maximumContainerElements: 4,
        maximumStringBytes: limits.maximumCARHeaderBytes
      ).decode(Header.self, from: headerBytes)
    } catch {
      throw RepoVerificationError.malformedCARHeader
    }

    guard header.version == 1 else {
      throw RepoVerificationError.unsupportedCARVersion(header.version)
    }
    guard header.roots.count == 2 else {
      throw RepoVerificationError.invalidCARRootCount(actual: header.roots.count)
    }
    guard header.roots.allSatisfy(Self.isPermissionedRepoCID) else {
      throw RepoVerificationError.malformedCARCID
    }
    return header.roots
  }

  func requiredBlock(maximumPayloadBytes: Int) async throws -> PermissionedRepoCARBlock {
    guard let block = try await readBlock(maximumPayloadBytes: maximumPayloadBytes) else {
      throw RepoVerificationError.truncatedCAR
    }
    return block
  }

  func readBlock(maximumPayloadBytes: Int) async throws -> PermissionedRepoCARBlock? {
    guard let encodedLength = try await readUnsignedVarint() else { return nil }
    guard encodedLength >= Self.cidLength else {
      throw RepoVerificationError.malformedCARCID
    }

    let payloadLength = encodedLength - UInt64(Self.cidLength)
    guard maximumPayloadBytes >= 0, payloadLength <= UInt64(maximumPayloadBytes) else {
      throw RepoVerificationError.inputTooLarge(
        limit: maximumPayloadBytes,
        actual: Int(exactly: payloadLength) ?? Int.max)
    }

    let cidBytes = try await readExactly(Self.cidLength)
    guard cidBytes.starts(with: Self.cidPrefix), let cid = try? LexLink(cidBytes) else {
      throw RepoVerificationError.malformedCARCID
    }
    let bytes = try await readExactly(Int(payloadLength))
    let digest = Data(SHA256.hash(data: bytes))
    guard digest.elementsEqual(cidBytes.suffix(32)) else {
      throw RepoVerificationError.carBlockCIDMismatch(cid)
    }
    return PermissionedRepoCARBlock(cid: cid, bytes: bytes)
  }

  private func readUnsignedVarint() async throws -> UInt64? {
    var value: UInt64 = 0
    var byteCount = 0

    while byteCount < 10 {
      guard let byte = try await readByte() else {
        if byteCount == 0 { return nil }
        throw RepoVerificationError.truncatedCAR
      }
      let payload = UInt64(byte & 0x7f)
      if byteCount == 9, payload > 1 {
        throw RepoVerificationError.malformedCARVarint
      }
      value |= payload << UInt64(byteCount * 7)
      byteCount += 1

      if byte & 0x80 == 0 {
        if byteCount > 1, payload == 0 {
          throw RepoVerificationError.malformedCARVarint
        }
        return value
      }
    }
    throw RepoVerificationError.malformedCARVarint
  }

  private func readByte() async throws -> UInt8? {
    while buffered.isEmpty {
      guard let chunk = try await iterator.next() else { return nil }
      buffered = chunk
    }
    return buffered.removeFirst()
  }

  private func readExactly(_ count: Int) async throws -> Data {
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      while buffered.isEmpty {
        guard let chunk = try await iterator.next() else {
          throw RepoVerificationError.truncatedCAR
        }
        buffered = chunk
      }
      let consumed = min(count - result.count, buffered.count)
      result.append(contentsOf: buffered.prefix(consumed))
      buffered = buffered.dropFirst(consumed)
    }
    return result
  }

  private static func isPermissionedRepoCID(_ link: LexLink) -> Bool {
    link.cid.rawBuffer.count == cidLength && link.cid.rawBuffer.starts(with: cidPrefix)
  }

  private struct Header: Decodable {
    let roots: [LexLink]
    let version: Int
  }
}

private final class ConsumptionState: @unchecked Sendable {
  private let lock = NSLock()
  private var iterationStarted = false

  func beginIteration() -> Bool {
    lock.withLock {
      guard !iterationStarted else { return false }
      iterationStarted = true
      return true
    }
  }
}
