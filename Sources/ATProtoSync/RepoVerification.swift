import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor

/// Resource limits applied while decoding and verifying Permissioned Data repositories.
public struct RepoVerificationLimits: Hashable, Sendable {
  /// The largest encoded commit accepted as STAR metadata.
  ///
  /// The `atproto-space-repo` profile limits metadata to 64 KiB, the default.
  public var maximumCommitBytes: Int

  /// The largest record path accepted as a STAR key.
  ///
  /// The `atproto-space-repo` profile limits keys to 4 KiB, the default.
  public var maximumRecordPathBytes: Int

  /// The largest DRISL encoding of a record accepted as a STAR value.
  ///
  /// The `atproto-space-repo` profile limits values to 1 MiB, the default,
  /// and repo hosts refuse to write a larger space record.
  public var maximumRecordBytes: Int

  /// The largest number of records accepted in one repository.
  public var maximumRecords: Int

  /// The largest nesting depth accepted from DRISL input.
  public var maximumNestingDepth: Int

  /// Creates verification limits suitable for client-side repository sync.
  public init(
    maximumCommitBytes: Int = 64 * 1024,
    maximumRecordPathBytes: Int = 4 * 1024,
    maximumRecordBytes: Int = 1024 * 1024,
    maximumRecords: Int = 100_000,
    maximumNestingDepth: Int = 16
  ) {
    self.maximumCommitBytes = maximumCommitBytes
    self.maximumRecordPathBytes = maximumRecordPathBytes
    self.maximumRecordBytes = maximumRecordBytes
    self.maximumRecords = maximumRecords
    self.maximumNestingDepth = maximumNestingDepth
  }
}

/// A failure to decode or verify a Permissioned Data repository state.
public enum RepoVerificationError: Error, Hashable, Sendable {
  /// An encoded input exceeded its configured byte or count limit.
  case inputTooLarge(limit: Int, actual: Int)

  /// A STAR archive did not start with the STAR magic bytes.
  case invalidSTARMagic

  /// A STAR frame length used an invalid or non-minimal unsigned varint.
  case malformedSTARVarint

  /// A STAR archive ended before the `0x00` that terminates it: inside a
  /// frame, between a key and its value, or where a control byte belongs.
  case truncatedSTAR

  /// The byte after the STAR metadata or a pair was neither `0x01`, which
  /// starts another pair, nor `0x00`, which ends the archive.
  case invalidSTARControlByte(UInt8)

  /// Bytes followed the `0x00` that terminates a STAR archive.
  case trailingSTARBytes

  /// The STAR metadata was not a canonical DRISL commit of the
  /// `atproto-space-repo` profile.
  case malformedCommit

  /// A STAR record path did not follow the previous one in strict
  /// lexicographic byte order, so it was out of order or a duplicate.
  case recordOutOfOrder(String)

  /// A STAR record value was not a canonical DRISL map.
  case malformedRecord(String)

  /// The record sequence was consumed more than once.
  case recordsAlreadyConsumed

  /// A checkpoint was requested before the record sequence reached its end.
  case incompleteRepository

  /// A persisted LtHash state had a size other than 2048 bytes.
  case invalidLtHashStateLength(actual: Int)

  /// A repository path was not a valid collection and record-key pair.
  case malformedRecordPath(String)

  /// A generated incremental operation contained invalid fields.
  case malformedOperation

  /// The commit format version is not supported.
  case unsupportedCommitVersion(Int)

  /// A commit field was malformed or had the wrong length.
  case invalidCommitField(field: String)

  /// The commit's `repo` or `space` is not the one that was requested.
  case commitIdentityMismatch

  /// The response MAC did not authenticate the commit: it is missing,
  /// malformed, does not verify, or covers an `Atproto-Space-Commit` field
  /// that describes another commit (`fieldMismatch`).
  case invalidMAC(SpaceMACError)

  /// The local LtHash digest did not match the authenticated commit data.
  case setHashMismatch

  /// An incremental response tried to replace a newer durable checkpoint.
  case staleCommitRevision(checkpoint: TID, commit: TID)
}

/// What authenticates the commit in one response: the repo and space that were
/// requested, the encapsulation the MAC was requested with, and the response
/// fields that carry the MAC.
///
/// Create a new `ATProtoCrypto.SpaceKeyEncapsulation` for each request, send
/// `ATProtoCrypto.SpaceMAC.acceptSignature(profile:keyShare:)` with the
/// `atproto-space-commit` profile in `Accept-Signature`, and read the response
/// with `ATProtoCrypto.SpaceMACResponse`.
public struct RepoCommitAuthentication: Sendable {
  /// The space that was requested.
  public let space: SpaceRef

  /// The DID of the repo that was requested.
  public let repo: SwiftAtproto.DID

  /// The key share and secret the MAC was requested with.
  public let encapsulation: SpaceKeyEncapsulation

  /// The `Atproto-Space-Commit`, `Signature-Input`, and `Signature` fields of
  /// the response.
  public let response: SpaceMACResponse

  /// Creates the authentication for one response.
  public init(
    space: SpaceRef, repo: SwiftAtproto.DID, encapsulation: SpaceKeyEncapsulation,
    response: SpaceMACResponse
  ) {
    self.space = space
    self.repo = repo
    self.encapsulation = encapsulation
    self.response = response
  }
}

/// Decodes and authenticates Permissioned Data repository commits.
public enum RepoCommitVerifier {
  /// Checks the commit's version, fields, and identity, then its MAC and that
  /// the `Atproto-Space-Commit` field the MAC covers describes it, and
  /// returns its revision. Only after this succeeds is `data` the author's
  /// claim about the repo.
  ///
  /// This does not compare `data` with a local repository state. Use
  /// ``RepoCommit/verify(_:authentication:)`` when one is available.
  @discardableResult
  public static func verify(
    _ commit: any PermissionedRepoCommitDescribing,
    authentication: RepoCommitAuthentication
  ) throws -> TID {
    guard commit.permissionedRepoCommitVersion == 1 else {
      throw RepoVerificationError.unsupportedCommitVersion(commit.permissionedRepoCommitVersion)
    }
    guard commit.permissionedRepoCommitData.count == 32 else {
      throw RepoVerificationError.invalidCommitField(field: "data")
    }
    guard let revision = commit.permissionedRepoCommitRevision.typed else {
      throw RepoVerificationError.invalidCommitField(field: "rev")
    }
    guard commit.permissionedRepoCommitRepo.rawValue == authentication.repo.rawValue,
      commit.permissionedRepoCommitSpace.rawValue == authentication.space.rawValue
    else {
      throw RepoVerificationError.commitIdentityMismatch
    }
    do {
      try SpaceMAC.verifyCommit(
        authentication.response,
        commit: SpaceMACCommitField(
          ver: commit.permissionedRepoCommitVersion,
          repo: commit.permissionedRepoCommitRepo.rawValue,
          space: commit.permissionedRepoCommitSpace.rawValue,
          rev: commit.permissionedRepoCommitRevision.rawValue,
          data: commit.permissionedRepoCommitData),
        encapsulation: authentication.encapsulation)
    } catch let error as SpaceMACError {
      throw RepoVerificationError.invalidMAC(error)
    }
    return revision
  }
}

func drislDecoder(
  maximumNestingDepth: Int,
  maximumContainerElements: Int,
  maximumStringBytes: Int
) -> CborDecoder {
  CborDecoder(
    options: [
      .minimalArgumentEncoding,
      .definiteLengthItems,
      .lexicographicallySortedMapKeys,
      .stringMapKeysOnly,
      .basicSimpleValuesOnly,
      .validUTF8Only,
      .singleTopLevelItem,
      .floatingPointValuesDisallowed,
    ],
    allowedTags: [42],
    limits: .init(
      maximumNestingDepth: maximumNestingDepth,
      maximumContainerElements: maximumContainerElements,
      maximumStringBytes: maximumStringBytes)
  )
}
