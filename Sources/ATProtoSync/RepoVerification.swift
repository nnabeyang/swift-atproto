import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor

/// Resource limits applied while decoding and verifying Permissioned Data repositories.
public struct RepoVerificationLimits: Hashable, Sendable {
  /// The largest encoded signed commit accepted by the DRISL decoder.
  public var maximumCommitBytes: Int

  /// The largest encoded repository index accepted by the DRISL decoder.
  public var maximumIndexBytes: Int

  /// The largest number of entries accepted in a repository index.
  public var maximumIndexEntries: Int

  /// The largest nesting depth accepted from DRISL input.
  public var maximumNestingDepth: Int

  /// The largest signature accepted before public-key verification.
  public var maximumSignatureBytes: Int

  /// Creates verification limits suitable for client-side repository sync.
  public init(
    maximumCommitBytes: Int = 64 * 1024,
    maximumIndexBytes: Int = 64 * 1024 * 1024,
    maximumIndexEntries: Int = 100_000,
    maximumNestingDepth: Int = 16,
    maximumSignatureBytes: Int = 256
  ) {
    self.maximumCommitBytes = maximumCommitBytes
    self.maximumIndexBytes = maximumIndexBytes
    self.maximumIndexEntries = maximumIndexEntries
    self.maximumNestingDepth = maximumNestingDepth
    self.maximumSignatureBytes = maximumSignatureBytes
  }
}

/// A failure to decode or verify a Permissioned Data repository state.
public enum RepoVerificationError: Error, Hashable, Sendable {
  /// An encoded input exceeded its configured byte limit.
  case inputTooLarge(limit: Int, actual: Int)

  /// A persisted LtHash state had a size other than 2048 bytes.
  case invalidLtHashStateLength(actual: Int)

  /// A signed commit could not be decoded as canonical DRISL.
  case malformedSignedCommit

  /// A repository index could not be decoded as canonical DRISL.
  case malformedRepositoryIndex

  /// A repository index path was not a valid collection and record-key pair.
  case malformedRecordPath(String)

  /// A generated incremental operation contained invalid fields.
  case malformedOperation

  /// The signed commit format version is not supported.
  case unsupportedCommitVersion(Int)

  /// A fixed-size signed commit field had the wrong byte length.
  case invalidCommitFieldLength(field: String, expected: Int, actual: Int)

  /// A variable-size signed commit field was empty or exceeded its limit.
  case invalidCommitField(field: String)

  /// A context field cannot be represented by its uint16 length prefix.
  case contextFieldTooLong

  /// The signed commit revision did not match the supplied context.
  case revisionMismatch

  /// The hash-binding MAC did not authenticate the claimed repository hash.
  case macMismatch

  /// The author key did not verify the commit context signature.
  case signatureMismatch

  /// The local LtHash digest did not match the authenticated commit hash.
  case setHashMismatch
}

/// The identity and revision bound into a Permissioned Data signed commit.
public struct RepoCommitContext: Hashable, Sendable {
  /// The permissioned space being synchronized.
  public let space: SpaceRef

  /// The DID of the repository author.
  public let author: SwiftAtproto.DID

  /// The repository revision claimed by the signed commit.
  public let revision: TID

  /// Creates a signed commit context.
  public init(space: SpaceRef, author: SwiftAtproto.DID, revision: TID) {
    self.space = space
    self.author = author
    self.revision = revision
  }

  /// Encodes the domain-separated context signed by a repository author.
  ///
  /// Each field is prefixed by its big-endian uint16 byte length. This is
  /// deliberately independent from LtHash's little-endian lane encoding.
  public func encoded(inputKeyMaterial: Data) throws -> Data {
    let fields = [
      Data(space.rawValue.utf8),
      Data(author.rawValue.utf8),
      Data(revision.rawValue.utf8),
      inputKeyMaterial,
    ]
    guard fields.allSatisfy({ $0.count <= Int(UInt16.max) }) else {
      throw RepoVerificationError.contextFieldTooLong
    }

    var output = Data("atproto-space-v1".utf8)
    for field in fields {
      let length = UInt16(field.count)
      output.append(UInt8(length >> 8))
      output.append(UInt8(length & 0xff))
      output.append(field)
    }
    return output
  }
}

/// Decodes and authenticates Permissioned Data signed commits.
public enum SignedRepoCommitVerifier {
  /// Decodes a generated signed commit type from canonical DRISL bytes.
  ///
  /// - Throws: ``RepoVerificationError/malformedSignedCommit`` when decoding
  ///   fails, or ``RepoVerificationError/inputTooLarge(limit:actual:)`` before
  ///   decoding an oversized block.
  public static func decode<Commit>(
    _ type: Commit.Type,
    fromDRISL data: Data,
    limits: RepoVerificationLimits = .init()
  ) throws -> Commit where Commit: Decodable & PermissionedRepoSignedCommitDescribing {
    guard data.count <= limits.maximumCommitBytes else {
      throw RepoVerificationError.inputTooLarge(
        limit: limits.maximumCommitBytes, actual: data.count)
    }
    do {
      return try drislDecoder(
        maximumNestingDepth: limits.maximumNestingDepth,
        maximumContainerElements: 64,
        maximumStringBytes: limits.maximumCommitBytes
      ).decode(type, from: data)
    } catch {
      throw RepoVerificationError.malformedSignedCommit
    }
  }

  /// Verifies a signed commit's context, hash-binding MAC, and author signature.
  ///
  /// This authenticates the commit's hash claim but does not compare it with a
  /// local repository state. Use ``RepoCommit/verify(_:context:publicKey:limits:)``
  /// when a local state is available.
  public static func verify(
    _ commit: any PermissionedRepoSignedCommitDescribing,
    context: RepoCommitContext,
    publicKey: PublicKey,
    limits: RepoVerificationLimits = .init()
  ) throws {
    guard commit.permissionedRepoCommitVersion == 1 else {
      throw RepoVerificationError.unsupportedCommitVersion(
        commit.permissionedRepoCommitVersion)
    }
    try requireLength(commit.permissionedRepoCommitHash, field: "hash", expected: 32)
    try requireLength(
      commit.permissionedRepoCommitInputKeyMaterial, field: "ikm", expected: 32)
    try requireLength(commit.permissionedRepoCommitMAC, field: "mac", expected: 32)

    let signature = commit.permissionedRepoCommitSignature
    guard !signature.isEmpty, signature.count <= limits.maximumSignatureBytes else {
      throw RepoVerificationError.invalidCommitField(field: "sig")
    }
    guard commit.permissionedRepoCommitRevision.typed != nil else {
      throw RepoVerificationError.invalidCommitField(field: "rev")
    }
    guard commit.permissionedRepoCommitRevision.rawValue == context.revision.rawValue else {
      throw RepoVerificationError.revisionMismatch
    }

    let contextBytes = try context.encoded(
      inputKeyMaterial: commit.permissionedRepoCommitInputKeyMaterial)
    let macKey = HKDF<SHA256>.expand(
      pseudoRandomKey: SymmetricKey(
        data: commit.permissionedRepoCommitInputKeyMaterial),
      info: contextBytes,
      outputByteCount: 32
    )
    guard
      HMAC<SHA256>.isValidAuthenticationCode(
        commit.permissionedRepoCommitMAC,
        authenticating: commit.permissionedRepoCommitHash,
        using: macKey)
    else {
      throw RepoVerificationError.macMismatch
    }
    guard
      publicKey.isValidSignature(
        signature: signature,
        for: contextBytes)
    else {
      throw RepoVerificationError.signatureMismatch
    }
  }

  private static func requireLength(_ data: Data, field: String, expected: Int) throws {
    guard data.count == expected else {
      throw RepoVerificationError.invalidCommitFieldLength(
        field: field, expected: expected, actual: data.count)
    }
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
