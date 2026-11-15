import Crypto
import Foundation
import Testing

@testable import ATProtoCrypto

struct SpaceMACTests {
  private static let space = "at://did:example:space/space/app.bsky.group/test"
  private static let repo = "did:example:alice"
  private static let rev = "3kbcq3p7ad400"
  private static let data = Data(repeating: 1, count: 32)
  private static let uri = "at://did:example:alice/space/app.bsky.group/test/app.bsky.feed.post/1"
  // The CIDs of `{ text: 'hello' }` and `{ text: 'world' }` in the upstream tests.
  private static let cidA = hex("017112206428f02304b8db8cb107c89336481f0fead728bf374ca80168d2c71938cefae7")
  private static let secret = SymmetricKey(data: Data(0..<32))

  // MARK: - KEM

  @Test func bothSidesDeriveTheSameSecret() throws {
    let author = try PrivateKey(type: .p256)
    let encapsulation = try SpaceKeyEncapsulation.encapsulate(authorKEMKey: author.publicKey.did)
    #expect(encapsulation.keyShare.hasPrefix("did:key:zDn"))
    #expect(encapsulation.sharedSecret.bitCount == 256)
    #expect(
      try SpaceKeyEncapsulation.decapsulate(keyShare: encapsulation.keyShare, authorKEMKey: author)
        == encapsulation.sharedSecret)
  }

  @Test func acceptsTheMultibaseOfAVerificationMethod() throws {
    let author = try PrivateKey(type: .p256)
    let encapsulation = try SpaceKeyEncapsulation.encapsulate(
      authorKEMKey: author.publicKey.multibaseString)
    #expect(
      try SpaceKeyEncapsulation.decapsulate(keyShare: encapsulation.keyShare, authorKEMKey: author)
        == encapsulation.sharedSecret)
  }

  @Test func usesAFreshKeyShareEachTime() throws {
    let author = try PrivateKey(type: .p256).publicKey.did
    let first = try SpaceKeyEncapsulation.encapsulate(authorKEMKey: author)
    let second = try SpaceKeyEncapsulation.encapsulate(authorKEMKey: author)
    #expect(first.keyShare != second.keyShare)
    #expect(first.sharedSecret != second.sharedSecret)
  }

  @Test func anotherAuthorKeyDerivesAnotherSecret() throws {
    let author = try PrivateKey(type: .p256)
    let other = try PrivateKey(type: .p256)
    let encapsulation = try SpaceKeyEncapsulation.encapsulate(authorKEMKey: author.publicKey.did)
    #expect(
      try SpaceKeyEncapsulation.decapsulate(keyShare: encapsulation.keyShare, authorKEMKey: other)
        != encapsulation.sharedSecret)
  }

  @Test func rejectsKeysOtherThanP256() throws {
    let author = try PrivateKey(type: .p256)
    for type in [KeyType.secp256k1, .ed25519] {
      let key = try PrivateKey(type: type)
      #expect(throws: SpaceMACError.invalidKey) {
        try SpaceKeyEncapsulation.encapsulate(authorKEMKey: key.publicKey.did)
      }
      #expect(throws: SpaceMACError.invalidKey) {
        try SpaceKeyEncapsulation.decapsulate(keyShare: key.publicKey.did, authorKEMKey: author)
      }
      #expect(throws: SpaceMACError.invalidKey) {
        try SpaceKeyEncapsulation.decapsulate(keyShare: author.publicKey.did, authorKEMKey: key)
      }
    }
    for value in ["", "did:key:nope", "did:key:zDnae", "did:web:example.com", "zzz"] {
      #expect(throws: SpaceMACError.invalidKey) {
        try SpaceKeyEncapsulation.encapsulate(authorKEMKey: value)
      }
    }
  }

  // The base-mode, export-only DHKEM(P-256, HKDF-SHA256) entry of the HPKE test
  // vectors (github.com/cfrg/draft-irtf-cfrg-hpke, test-vectors.json at
  // b1f7cb0): mode 0, kem_id 16, kdf_id 1, aead_id 65535.
  private static let vectorEnc = hex(
    "04d804370b7e24b94749eb1dc8df6d4d4a5d75f9effad01739ebcad5c54a40d57aaa8b4190fc124dbde2e4f1e1d1b012a3bc4038157dc29b55533a932306d8d38d"
  )
  private static let vectorSkRm = hex("62c3868357a464f8461d03aa0182c7cebcde841036aea7230ddc7339f1088346")

  @Test(arguments: [
    ("", "8cf837d5bf1994f0fac3ee1faa671d07e9a38b7f6153bdbb8a66b90159ef7d13"),
    ("00", "3c7708f8ae1f510f4439fa514deb1c7ece7a29085a2e8270a84b6ad6481cc0b4"),
    ("54657374436f6e74657874", "f53fb127f67dabf35b14fae14b53e6ce5c49e572f95eb4ef7a3b3cb9cd85f12b"),
  ])
  func matchesTheHPKEExportVectors(context: String, exported: String) throws {
    let author = try PrivateKey(type: .p256, rawValue: Self.vectorSkRm)
    let secret = try SpaceKeyEncapsulation.export(
      enc: Self.vectorEnc, authorKEMKey: author,
      info: Self.hex("4f6465206f6e2061204772656369616e2055726e"), context: Self.hex(context))
    #expect(secret.withUnsafeBytes { Data($0) } == Self.hex(exported))
  }

  // The same keys under `info` "atproto-mac" with an empty exporter context,
  // computed independently by following the proposal's "Shared secret without
  // HPKE" appendix in Python with hmac and hashlib, which reproduces the vectors
  // above under their `info`.
  @Test func matchesTheAppendixUnderTheAtprotoInfo() throws {
    let keyShare = PublicKey(
      type: .p256, raw: .p256(try P256.Signing.PublicKey(x963Representation: Self.vectorEnc))
    ).did
    let author = try PrivateKey(type: .p256, rawValue: Self.vectorSkRm)
    let secret = try SpaceKeyEncapsulation.decapsulate(keyShare: keyShare, authorKEMKey: author)
    #expect(
      secret.withUnsafeBytes { Data($0) }
        == Self.hex("2060e0558d1b34c10086bc137f849bb79ba59fcdc30544418e35c9cd301f0d0d"))
  }

  // MARK: - MACs

  // Computed independently from the formula in the proposal with Python's hmac.
  @Test func commitMACMatchesTheFormula() throws {
    let mac = try SpaceMAC.commitMAC(
      sharedSecret: Self.secret, space: Self.space, repo: Self.repo, rev: Self.rev, data: Self.data)
    #expect(mac == Self.hex("3b38727ea60248c55e0c549faa9a6738a14342eb57d779e6b300784f8b8d6acc"))
    #expect(
      SpaceMAC.isValidCommitMAC(
        mac, sharedSecret: Self.secret, space: Self.space, repo: Self.repo, rev: Self.rev,
        data: Self.data))
  }

  @Test func commitMACCoversEveryField() throws {
    let mac = try SpaceMAC.commitMAC(
      sharedSecret: Self.secret, space: Self.space, repo: Self.repo, rev: Self.rev, data: Self.data)
    let changes: [(SymmetricKey, String, String, String, Data)] = [
      (SymmetricKey(size: .bits256), Self.space, Self.repo, Self.rev, Self.data),
      (Self.secret, Self.space + "2", Self.repo, Self.rev, Self.data),
      (Self.secret, Self.space, "did:example:bob", Self.rev, Self.data),
      (Self.secret, Self.space, Self.repo, "3kbcq3p7ad401", Self.data),
      (Self.secret, Self.space, Self.repo, Self.rev, Data(repeating: 2, count: 32)),
    ]
    for (secret, space, repo, rev, data) in changes {
      #expect(
        !SpaceMAC.isValidCommitMAC(
          mac, sharedSecret: secret, space: space, repo: repo, rev: rev, data: data))
    }
  }

  @Test func commitMACIsUnambiguousAcrossFieldBoundaries() throws {
    // Without length prefixes these two would MAC identically.
    let a = try SpaceMAC.commitMAC(
      sharedSecret: Self.secret, space: Self.space, repo: "did:example:alice", rev: "3kbc",
      data: Self.data)
    let b = try SpaceMAC.commitMAC(
      sharedSecret: Self.secret, space: Self.space, repo: "did:example:alice3", rev: "kbc",
      data: Self.data)
    #expect(a != b)
  }

  @Test func recordMACMatchesTheFormula() throws {
    let mac = try SpaceMAC.recordMAC(sharedSecret: Self.secret, uri: Self.uri, cid: Self.cidA)
    #expect(mac == Self.hex("b1000cbab95db1e15987c90d63eb3bdc76dbd64b921ca0ef5af842ad588da4c9"))
    #expect(SpaceMAC.isValidRecordMAC(mac, sharedSecret: Self.secret, uri: Self.uri, cid: Self.cidA))
    #expect(!SpaceMAC.isValidRecordMAC(mac, sharedSecret: Self.secret, uri: Self.uri + "2", cid: Self.cidA))
    var otherCID = Self.cidA
    otherCID[otherCID.count - 1] ^= 1
    #expect(!SpaceMAC.isValidRecordMAC(mac, sharedSecret: Self.secret, uri: Self.uri, cid: otherCID))
  }

  @Test func rejectsFieldsLongerThanTheLengthPrefix() {
    let long = String(repeating: "a", count: Int(UInt16.max) + 1)
    #expect(throws: SpaceMACError.fieldTooLong) {
      try SpaceMAC.commitMAC(
        sharedSecret: Self.secret, space: long, repo: Self.repo, rev: Self.rev, data: Self.data)
    }
    #expect(
      !SpaceMAC.isValidCommitMAC(
        Data(count: 32), sharedSecret: Self.secret, space: long, repo: Self.repo, rev: Self.rev,
        data: Self.data))
  }

  // MARK: - Headers

  @Test func formatsBothHeadersAsUpstreamDoes() {
    #expect(
      SpaceMAC.wantMACHeader(type: .repo, keyShare: "did:key:zDnaExample")
        == "type=\"atproto-space-repo\", ver=1, key_share=\"did:key:zDnaExample\"")
    #expect(
      SpaceMAC.macHeader(type: .repo, mac: Data(0..<32))
        == "type=\"atproto-space-repo\", ver=1, mac=:AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=:")
  }

  @Test func roundTripsBothHeaders() throws {
    let want = SpaceMAC.wantMACHeader(type: .record, keyShare: "did:key:zDnaX")
    #expect(try SpaceMAC.keyShare(fromWantMACHeader: want, type: .record) == "did:key:zDnaX")
    let mac = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    #expect(try SpaceMAC.mac(fromMACHeader: SpaceMAC.macHeader(type: .record, mac: mac), type: .record) == mac)
  }

  @Test func toleratesWhitespaceParametersAndMissingPadding() throws {
    let header = "ver=1 ,type=\"atproto-space-repo\";a=1,   mac=:AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8:;b"
    #expect(try SpaceMAC.mac(fromMACHeader: header, type: .repo) == Data(0..<32))
  }

  @Test func rejectsAMissingOrMalformedHeader() {
    #expect(throws: SpaceMACError.missingHeader) {
      try SpaceMAC.keyShare(fromWantMACHeader: nil, type: .repo)
    }
    for value in ["???", "type=\"atproto-space-repo\",", "Type=\"atproto-space-repo\"", "type=\"unterminated"] {
      #expect(throws: SpaceMACError.malformedHeader) {
        try SpaceMAC.keyShare(fromWantMACHeader: value, type: .repo)
      }
    }
    #expect(throws: SpaceMACError.malformedHeader) {
      try SpaceMAC.keyShare(fromWantMACHeader: "type=\"atproto-space-repo\", ver=1", type: .repo)
    }
    #expect(throws: SpaceMACError.malformedHeader) {
      try SpaceMAC.mac(fromMACHeader: "type=\"atproto-space-repo\", ver=1, mac=\"abc\"", type: .repo)
    }
    #expect(throws: SpaceMACError.malformedHeader) {
      try SpaceMAC.mac(fromMACHeader: "type=\"atproto-space-repo\", ver=1, mac=(:AA==:)", type: .repo)
    }
  }

  @Test func rejectsAnotherTypeOrVersion() {
    let want = SpaceMAC.wantMACHeader(type: .repo, keyShare: "did:key:zDnaX")
    #expect(throws: SpaceMACError.unsupportedType) {
      try SpaceMAC.keyShare(fromWantMACHeader: want, type: .record)
    }
    #expect(throws: SpaceMACError.unsupportedType) {
      try SpaceMAC.mac(fromMACHeader: "type=atproto-space-repo, ver=1, mac=:AA==:", type: .repo)
    }
    #expect(throws: SpaceMACError.unsupportedVersion) {
      try SpaceMAC.keyShare(
        fromWantMACHeader: "type=\"atproto-space-repo\", ver=2, key_share=\"did:key:zDnaX\"", type: .repo)
    }
    #expect(throws: SpaceMACError.unsupportedVersion) {
      try SpaceMAC.keyShare(
        fromWantMACHeader: "type=\"atproto-space-repo\", ver=\"1\", key_share=\"did:key:zDnaX\"", type: .repo)
    }
  }

  private static func hex(_ string: String) -> Data {
    var data = Data()
    var index = string.startIndex
    while index < string.endIndex {
      let next = string.index(index, offsetBy: 2)
      data.append(UInt8(string[index..<next], radix: 16)!)
      index = next
    }
    return data
  }
}
