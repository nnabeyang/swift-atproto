import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto
import SwiftCbor
import Testing

@testable import ATProtoSync

@Suite("Permissioned repository signed commits")
struct SignedRepoCommitTests {
  private let context = RepoCommitContext(
    space: try! SpaceRef(
      string:
        "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/test"),
    author: try! SwiftAtproto.DID(string: "did:plc:ewvi7nxzyoun6zhxrhs64oiz"),
    revision: try! TID(string: "3kbgyjzqfeq2e"))
  private let key = try! PrivateKey(
    type: .ed25519, rawValue: Data(repeating: 7, count: 32))

  @Test func contextAndMACMatchTheNodeReferenceVector() throws {
    let ikm = Data((0..<32).map(UInt8.init))
    let hash = Data(
      hex: "ae05cb6d224379d9710c290c8529945c5b0e0fde9ead30b9699057ce701c63e7")
    let contextBytes = try context.encoded(inputKeyMaterial: ikm)
    #expect(
      contextBytes.hex == "617470726f746f2d73706163652d7631004261743a2f2f6469643a706c633a65777669376e787a796f756e367a687872687336346f697a2f73706163652f636f6d2e6578616d706c652e666f72756d2f7465737400206469643a706c633a65777669376e787a796f756e367a687872687336346f697a000d336b6267796a7a7166657132650020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")

    let commit = try signedCommit(hash: hash, ikm: ikm)
    #expect(commit.mac.hex == "a3229b8c8e136ad0886d7bc9cbf75ac73a7f90b9c487dab5bcb879fd5a203160")
    try SignedRepoCommitVerifier.verify(
      commit, context: context, publicKey: key.publicKey)
  }

  @Test func decodesCanonicalDRISLAndRejectsTrailingData() throws {
    let commit = try signedCommit(hash: Data(repeating: 5, count: 32))
    let encoded = try CborEncoder(options: .lexicographicallySortedMapKeys).encode(commit)
    let decoded = try SignedRepoCommitVerifier.decode(
      TestSignedCommit.self, fromDRISL: encoded)
    #expect(decoded == commit)

    var trailing = encoded
    trailing.append(0)
    #expect(throws: RepoVerificationError.malformedSignedCommit) {
      try SignedRepoCommitVerifier.decode(TestSignedCommit.self, fromDRISL: trailing)
    }
    #expect(
      throws: RepoVerificationError.inputTooLarge(
        limit: encoded.count - 1, actual: encoded.count)
    ) {
      try SignedRepoCommitVerifier.decode(
        TestSignedCommit.self,
        fromDRISL: encoded,
        limits: RepoVerificationLimits(maximumCommitBytes: encoded.count - 1))
    }

    #expect(throws: RepoVerificationError.malformedSignedCommit) {
      try SignedRepoCommitVerifier.decode(
        TestSignedCommit.self, fromDRISL: Data([0xbf, 0xff]))
    }
    #expect(throws: RepoVerificationError.malformedSignedCommit) {
      try SignedRepoCommitVerifier.decode(
        TestSignedCommit.self,
        fromDRISL: Data([0xa1, 0x63, 0x76, 0x65, 0x72, 0x18, 0x01]))
    }
  }

  @Test func rejectsAnOversizedContextField() {
    #expect(throws: RepoVerificationError.contextFieldTooLong) {
      try context.encoded(inputKeyMaterial: Data(repeating: 0, count: 65_536))
    }
  }

  @Test func repositoryVerificationAcceptsTheMatchingState() throws {
    var repository = LtHash()
    repository.add("one")
    repository.add("two")
    let commit = try signedCommit(hash: repository.digest)

    try RepoCommit(state: repository.state).verify(
      commit, context: context, publicKey: key.publicKey)
  }

  @Test func rejectsUnsupportedVersionAndMalformedFields() throws {
    let valid = try signedCommit(hash: Data(repeating: 5, count: 32))
    var unsupported = valid
    unsupported.ver = 2
    #expect(throws: RepoVerificationError.unsupportedCommitVersion(2)) {
      try SignedRepoCommitVerifier.verify(
        unsupported, context: context, publicKey: key.publicKey)
    }

    var shortHash = valid
    shortHash.hash = Data(repeating: 0, count: 31)
    #expect(
      throws: RepoVerificationError.invalidCommitFieldLength(
        field: "hash", expected: 32, actual: 31)
    ) {
      try SignedRepoCommitVerifier.verify(
        shortHash, context: context, publicKey: key.publicKey)
    }

    var oversizedSignature = valid
    oversizedSignature.sig = Data(repeating: 0, count: 257)
    #expect(throws: RepoVerificationError.invalidCommitField(field: "sig")) {
      try SignedRepoCommitVerifier.verify(
        oversizedSignature, context: context, publicKey: key.publicKey)
    }
  }

  @Test func rejectsRevisionContextHashMACSignatureAndStateChanges() throws {
    let valid = try signedCommit(hash: Data(repeating: 5, count: 32))

    var revision = valid
    revision.rev = .init(rawValue: "3kbgyjzqfeq2f")
    #expect(throws: RepoVerificationError.revisionMismatch) {
      try SignedRepoCommitVerifier.verify(
        revision, context: context, publicKey: key.publicKey)
    }

    let otherContext = RepoCommitContext(
      space: try SpaceRef(
        string:
          "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/other"),
      author: context.author,
      revision: context.revision)
    #expect(throws: RepoVerificationError.macMismatch) {
      try SignedRepoCommitVerifier.verify(
        valid, context: otherContext, publicKey: key.publicKey)
    }

    let otherAuthor = RepoCommitContext(
      space: context.space,
      author: try SwiftAtproto.DID(string: "did:plc:ragtjsm2j2vknwkz3zp4oxrd"),
      revision: context.revision)
    #expect(throws: RepoVerificationError.macMismatch) {
      try SignedRepoCommitVerifier.verify(
        valid, context: otherAuthor, publicKey: key.publicKey)
    }

    var ikm = valid
    ikm.ikm[0] ^= 0xff
    #expect(throws: RepoVerificationError.macMismatch) {
      try SignedRepoCommitVerifier.verify(ikm, context: context, publicKey: key.publicKey)
    }

    var hash = valid
    hash.hash[0] ^= 0xff
    #expect(throws: RepoVerificationError.macMismatch) {
      try SignedRepoCommitVerifier.verify(hash, context: context, publicKey: key.publicKey)
    }

    var mac = valid
    mac.mac[0] ^= 0xff
    #expect(throws: RepoVerificationError.macMismatch) {
      try SignedRepoCommitVerifier.verify(mac, context: context, publicKey: key.publicKey)
    }

    var signature = valid
    signature.sig[0] ^= 0xff
    #expect(throws: RepoVerificationError.signatureMismatch) {
      try SignedRepoCommitVerifier.verify(
        signature, context: context, publicKey: key.publicKey)
    }

    var malformedRevision = valid
    malformedRevision.rev = .init(rawValue: "not-a-tid")
    #expect(throws: RepoVerificationError.invalidCommitField(field: "rev")) {
      try SignedRepoCommitVerifier.verify(
        malformedRevision, context: context, publicKey: key.publicKey)
    }

    #expect(throws: RepoVerificationError.setHashMismatch) {
      try RepoCommit().verify(valid, context: context, publicKey: key.publicKey)
    }
  }

  private func signedCommit(
    hash: Data,
    ikm: Data = Data((0..<32).map(UInt8.init))
  ) throws -> TestSignedCommit {
    let contextBytes = try context.encoded(inputKeyMaterial: ikm)
    let macKey = HKDF<SHA256>.expand(
      pseudoRandomKey: SymmetricKey(data: ikm),
      info: contextBytes,
      outputByteCount: 32)
    return TestSignedCommit(
      ver: 1,
      hash: hash,
      ikm: ikm,
      sig: try key.sign(contextBytes),
      mac: Data(HMAC<SHA256>.authenticationCode(for: hash, using: macKey)),
      rev: .init(rawValue: context.revision.rawValue))
  }
}

private struct TestSignedCommit: Codable, Hashable, PermissionedRepoSignedCommitDescribing {
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
