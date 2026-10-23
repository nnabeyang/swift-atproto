import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor

/// Resource limits applied while decoding and verifying Permissioned Data repositories.
public struct RepoVerificationLimits: Hashable, Sendable {
  /// The largest encoded commit accepted as STAR metadata.
  public var maximumCommitBytes: Int

  /// The largest record path accepted as a STAR key.
  public var maximumRecordPathBytes: Int

  /// The largest DRISL encoding of a record accepted as a STAR value.
  ///
  /// Repo hosts refuse to write a space record larger than 1 MiB, so a larger
  /// value is malformed.
  public var maximumRecordBytes: Int

  /// The largest number of records accepted in one repository.
  public var maximumRecords: Int

  /// The largest nesting depth accepted from DRISL input.
  public var maximumNestingDepth: Int

  /// Creates verification limits suitable for client-side repository sync.
  public init(
    maximumCommitBytes: Int = 64 * 1024,
    maximumRecordPathBytes: Int = 1024,
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

  /// A STAR archive did not start with the STAR-lite v1 magic bytes.
  case invalidSTARMagic

  /// A STAR frame length used an invalid or non-minimal unsigned varint.
  case malformedSTARVarint

  /// A STAR archive ended inside a frame or between a key and its value.
  case truncatedSTAR

  /// The STAR metadata was not a canonical DRISL commit of the
  /// `atproto-space-repo` profile.
  case malformedCommit

  /// A STAR record path did not follow the previous one in strict
  /// lexicographic byte order, so it was out of order or a duplicate.
  case recordOutOfOrder(String)

  /// A STAR record value was not a DRISL map.
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

  /// The response MAC did not authenticate the commit.
  case macMismatch

  /// The local LtHash digest did not match the authenticated commit data.
  case setHashMismatch

  /// An incremental response tried to replace a newer durable checkpoint.
  case staleCommitRevision(checkpoint: TID, commit: TID)
}

/// What authenticates the commit in one response: the repo and space that were
/// requested, the secret shared for that request, and the MAC its
/// `Atproto-Space-Mac` header carried.
///
/// Create the secret with `ATProtoCrypto.SpaceKeyEncapsulation` for each
/// request, and read the MAC with `ATProtoCrypto.SpaceMAC.mac(fromMACHeader:type:)`.
public struct RepoCommitAuthentication: Sendable {
  /// The space that was requested.
  public let space: SpaceRef

  /// The DID of the repo that was requested.
  public let repo: SwiftAtproto.DID

  /// The secret established for the request.
  public let sharedSecret: SymmetricKey

  /// The MAC from the response header.
  public let mac: Data

  /// Creates the authentication for one response.
  public init(space: SpaceRef, repo: SwiftAtproto.DID, sharedSecret: SymmetricKey, mac: Data) {
    self.space = space
    self.repo = repo
    self.sharedSecret = sharedSecret
    self.mac = mac
  }
}

/// Decodes and authenticates Permissioned Data repository commits.
public enum RepoCommitVerifier {
  /// Checks the commit's version, fields, and identity, then its MAC, and
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
    guard
      SpaceMAC.isValidCommitMAC(
        authentication.mac,
        sharedSecret: authentication.sharedSecret,
        space: commit.permissionedRepoCommitSpace.rawValue,
        repo: commit.permissionedRepoCommitRepo.rawValue,
        rev: commit.permissionedRepoCommitRevision.rawValue,
        data: commit.permissionedRepoCommitData)
    else {
      throw RepoVerificationError.macMismatch
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
