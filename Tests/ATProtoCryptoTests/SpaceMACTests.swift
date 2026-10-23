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

  // RFC 9180 §A.3.1, DHKEM(P-256, HKDF-SHA256): the syncer's key share is `pkEm`
  // and the author's KEM key is `skRm`. The upstream implementation checks the
  // same vector.
  @Test func matchesTheRFC9180Vector() throws {
    let pkEm = Self.hex(
      "04a92719c6195d5085104f469a8b9814d5838ff72b60501e2c4466e5e67b325ac98536d7b61a1af4b78e5b7f951c0900be863c403ce65c9bfcb9382657222d18c4"
    )
    let skRm = Self.hex("f3ce7fdae57e1a310d87f1ebbde6f328be0a99cdbcadf4d6589cf29de4b8ffd2")
    let expected = Self.hex("c0d26aeab536609a572b07695d933b589dcf363ff9d93c93adea537aeabb8cb8")

    let keyShare = PublicKey(
      type: .p256, raw: .p256(try P256.Signing.PublicKey(x963Representation: pkEm))
    ).did
    let author = try PrivateKey(type: .p256, rawValue: skRm)
    let secret = try SpaceKeyEncapsulation.decapsulate(keyShare: keyShare, authorKEMKey: author)
    #expect(secret.withUnsafeBytes { Data($0) } == expected)
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
