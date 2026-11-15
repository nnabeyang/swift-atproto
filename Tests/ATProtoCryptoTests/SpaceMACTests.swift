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

  // MARK: - HTTP message signatures

  // The P-256 did:key of the vector's `pkRm`, used where a fixed key share is
  // needed.
  private static let keyShare = "did:key:zDnaepxWioy4TQi6a94tSHKU4aqQkz6rksDiBfnuiGbwf4i5N"
  private static let commit = SpaceMACCommitField(ver: 1, repo: repo, space: space, rev: rev, data: data)
  private static let record = SpaceMACRecordField(
    uri: uri, cid: "bafyreidefhqcgbfy3ogledyjsm3eqh6k5mucwjelz4ub6r5yfq4myoxk5y")

  @Test func formatsAcceptSignature() {
    #expect(
      SpaceMAC.acceptSignature(profile: .commit, keyShare: Self.keyShare)
        == "mac=(\"atproto-space-commit\";sf);keyid=\"\(Self.keyShare)\";tag=\"atproto-space-commit\"")
    #expect(
      SpaceMAC.acceptSignature(profile: .record, keyShare: Self.keyShare)
        == "mac=(\"atproto-space-record\";sf);keyid=\"\(Self.keyShare)\";tag=\"atproto-space-record\"")
  }

  @Test(arguments: SpaceMACProfile.allCases)
  func hostReadsTheRequest(profile: SpaceMACProfile) throws {
    let value = SpaceMAC.acceptSignature(profile: profile, keyShare: Self.keyShare)
    let request = try #require(try SpaceMAC.request(fromAcceptSignature: value, profile: profile))
    #expect(request.profile == profile)
    #expect(request.label == "mac")
    #expect(request.keyShare == Self.keyShare)
    #expect("mac=" + request.signatureParameters == value)
  }

  @Test func hostFindsTheRequestByItsTagUnderAnyLabel() throws {
    let value =
      "a=(\"atproto-space-record\";sf);keyid=\"\(Self.keyShare)\";tag=\"atproto-space-record\", "
      + "sig1=(\"atproto-space-commit\";sf);keyid=\"\(Self.keyShare)\";tag=\"atproto-space-commit\";alg=\"hmac-sha256\""
    let request = try #require(try SpaceMAC.request(fromAcceptSignature: value, profile: .commit))
    #expect(request.label == "sig1")
    #expect(
      request.signatureParameters
        == "(\"atproto-space-commit\";sf);keyid=\"\(Self.keyShare)\";tag=\"atproto-space-commit\";alg=\"hmac-sha256\"")
  }

  @Test func hostFindsNoRequestWithoutTheProfilesTag() throws {
    #expect(try SpaceMAC.request(fromAcceptSignature: nil, profile: .commit) == nil)
    let record = SpaceMAC.acceptSignature(profile: .record, keyShare: Self.keyShare)
    #expect(try SpaceMAC.request(fromAcceptSignature: record, profile: .commit) == nil)
  }

  @Test func hostRejectsRequestsItCannotFulfill() {
    let components = "(\"atproto-space-commit\";sf)"
    let parameters = ";keyid=\"\(Self.keyShare)\";tag=\"atproto-space-commit\""
    let cases: [(String, SpaceMACError)] = [
      ("???", .malformedHeader),
      ("a=\(components)\(parameters), b=\(components)\(parameters)", .duplicateSignature),
      ("mac=(\"atproto-space-commit\")\(parameters)", .unexpectedComponents),
      ("mac=(\"atproto-space-record\";sf)\(parameters)", .unexpectedComponents),
      ("mac=(\"atproto-space-commit\";sf \"date\")\(parameters)", .unexpectedComponents),
      ("mac=\(components)\(parameters);created=1", .unsupportedParameter),
      ("mac=\(components)\(parameters);alg=\"hmac-sha512\"", .unsupportedAlgorithm),
      ("mac=\(components);tag=\"atproto-space-commit\"", .invalidKey),
      ("mac=\(components);keyid=\"did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK\";tag=\"atproto-space-commit\"", .invalidKey),
      ("mac=\(components);keyid=\"zDnaepxWioy4TQi6a94tSHKU4aqQkz6rksDiBfnuiGbwf4i5N\";tag=\"atproto-space-commit\"", .invalidKey),
    ]
    for (value, error) in cases {
      #expect(throws: error, "\(value)") {
        try SpaceMAC.request(fromAcceptSignature: value, profile: .commit)
      }
    }
  }

  // Computed independently with Python's hmac over the RFC 9421 signature base:
  //   "<profile>";sf: <field>
  //   "@signature-params": ("<profile>";sf);keyid="<key share>";tag="<profile>"
  @Test func commitMACMatchesTheSignatureBase() throws {
    let fields = try Self.responseFields(commit: Self.commit, secret: Self.secret)
    #expect(
      fields["atproto-space-commit"]
        == "ver=1, repo=\"did:example:alice\", space=\"at://did:example:space/space/app.bsky.group/test\", rev=\"3kbcq3p7ad400\", data=:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=:"
    )
    #expect(
      fields["signature-input"]
        == "mac=(\"atproto-space-commit\";sf);keyid=\"\(Self.keyShare)\";tag=\"atproto-space-commit\"")
    #expect(fields["signature"] == "mac=:1Uw9HH7OVxRdJVejRkW/UNwi0eUeNhYuELc4MjWzAMg=:")
    #expect(fields["vary"] == "accept-signature")
  }

  @Test func recordMACMatchesTheSignatureBase() throws {
    let fields = try Self.responseFields(record: Self.record, secret: Self.secret)
    #expect(
      fields["atproto-space-record"]
        == "uri=\"\(Self.uri)\", cid=\"bafyreidefhqcgbfy3ogledyjsm3eqh6k5mucwjelz4ub6r5yfq4myoxk5y\"")
    #expect(fields["signature"] == "mac=:z8uDF85XrpghKLc8vt82nanrIA2U+kcSdSGNZOeKewU=:")
  }

  @Test func verifiesWhatTheHostReturns() throws {
    let author = try PrivateKey(type: .p256)
    for profile in SpaceMACProfile.allCases {
      let encapsulation = try SpaceKeyEncapsulation.encapsulate(authorKEMKey: author.publicKey.did)
      let request = try #require(
        try SpaceMAC.request(
          fromAcceptSignature: SpaceMAC.acceptSignature(profile: profile, keyShare: encapsulation.keyShare),
          profile: profile))
      let secret = try SpaceKeyEncapsulation.decapsulate(keyShare: request.keyShare, authorKEMKey: author)
      switch profile {
      case .commit:
        let fields = try SpaceMAC.responseFields(commit: Self.commit, request: request, sharedSecret: secret)
        try SpaceMAC.verifyCommit(
          Self.response(fields, profile: profile), commit: Self.commit, encapsulation: encapsulation)
      case .record:
        let fields = try SpaceMAC.responseFields(record: Self.record, request: request, sharedSecret: secret)
        try SpaceMAC.verifyRecord(
          Self.response(fields, profile: profile), record: Self.record, encapsulation: encapsulation)
      }
    }
  }

  @Test func verifiesTheFieldAsAStructuredField() throws {
    var response = Self.response(
      try Self.responseFields(commit: Self.commit, secret: Self.secret), profile: .commit)
    // Other whitespace and missing padding serialize to the same canonical form.
    response.coveredField = try #require(response.coveredField)
      .replacingOccurrences(of: ", ", with: " ,\t")
      .replacingOccurrences(of: "AQE=:", with: "AQE:")
    try SpaceMAC.verifyCommit(response, commit: Self.commit, encapsulation: Self.encapsulation)
  }

  @Test func findsTheMACByItsTagUnderAnyLabel() throws {
    var response = Self.response(
      try Self.responseFields(commit: Self.commit, secret: Self.secret), profile: .commit)
    response.signatureInput = "other=(\"date\");tag=\"x\", sig1=" + response.signatureInput!.dropFirst(4)
    response.signature = "other=:AA==:, sig1=" + response.signature!.dropFirst(4)
    try SpaceMAC.verifyCommit(response, commit: Self.commit, encapsulation: Self.encapsulation)
  }

  @Test func rejectsMACsThatDoNotVerify() throws {
    let fields = try Self.responseFields(commit: Self.commit, secret: Self.secret)
    let valid = Self.response(fields, profile: .commit)
    let input = valid.signatureInput!
    let signature = valid.signature!
    let parameters = ";keyid=\"\(Self.keyShare)\";tag=\"atproto-space-commit\""
    let cases: [(SpaceMACResponse, SpaceMACError)] = [
      (.init(coveredField: nil, signatureInput: input, signature: signature), .missingHeader),
      (.init(coveredField: valid.coveredField, signatureInput: nil, signature: signature), .missingHeader),
      (.init(coveredField: valid.coveredField, signatureInput: input, signature: nil), .missingHeader),
      (.init(coveredField: "ver=", signatureInput: input, signature: signature), .malformedHeader),
      (.init(coveredField: valid.coveredField, signatureInput: input, signature: "mac=\"x\""), .missingSignature),
      (.init(coveredField: valid.coveredField, signatureInput: input, signature: "sig=" + signature.dropFirst(4)), .missingSignature),
      (.init(coveredField: valid.coveredField, signatureInput: input, signature: signature + ";p"), .missingSignature),
      (.init(coveredField: valid.coveredField, signatureInput: input + ", b=" + input.dropFirst(4), signature: signature), .duplicateSignature),
      (.init(coveredField: valid.coveredField, signatureInput: "mac=(\"atproto-space-commit\")" + parameters, signature: signature), .unexpectedComponents),
      (.init(coveredField: valid.coveredField, signatureInput: "mac=(\"atproto-space-commit\";sf \"date\")" + parameters, signature: signature), .unexpectedComponents),
      (.init(coveredField: valid.coveredField, signatureInput: input + ";alg=\"hmac-sha512\"", signature: signature), .unsupportedAlgorithm),
      (.init(coveredField: valid.coveredField, signatureInput: input.replacingOccurrences(of: Self.keyShare, with: "did:key:zDnaX"), signature: signature), .keyIDMismatch),
      (.init(coveredField: valid.coveredField, signatureInput: input + ";created=1", signature: signature), .macMismatch),
      (.init(coveredField: valid.coveredField!.replacingOccurrences(of: "3kbcq3p7ad400", with: "3kbcq3p7ad401"), signatureInput: input, signature: signature), .macMismatch),
    ]
    for (response, error) in cases {
      #expect(throws: error, "\(response)") {
        try SpaceMAC.verifyCommit(response, commit: Self.commit, encapsulation: Self.encapsulation)
      }
    }
    let otherSecret = SpaceKeyEncapsulation(keyShare: Self.keyShare, sharedSecret: SymmetricKey(size: .bits256))
    #expect(throws: SpaceMACError.macMismatch) {
      try SpaceMAC.verifyCommit(valid, commit: Self.commit, encapsulation: otherSecret)
    }
    // A record MAC carries the other tag, so no commit MAC is found.
    let record = Self.response(try Self.responseFields(record: Self.record, secret: Self.secret), profile: .record)
    #expect(throws: SpaceMACError.missingSignature) {
      try SpaceMAC.verifyCommit(
        .init(coveredField: valid.coveredField, signatureInput: record.signatureInput, signature: record.signature),
        commit: Self.commit, encapsulation: Self.encapsulation)
    }
  }

  @Test func rejectsAFieldThatDescribesAnotherCommit() throws {
    let response = Self.response(
      try Self.responseFields(commit: Self.commit, secret: Self.secret), profile: .commit)
    var others: [SpaceMACCommitField] = []
    for change in 0..<5 {
      var other = Self.commit
      switch change {
      case 0: other.ver = 2
      case 1: other.repo = "did:example:bob"
      case 2: other.space += "2"
      case 3: other.rev = "3kbcq3p7ad401"
      default: other.data = Data(repeating: 2, count: 32)
      }
      others.append(other)
    }
    for other in others {
      #expect(throws: SpaceMACError.fieldMismatch) {
        try SpaceMAC.verifyCommit(response, commit: other, encapsulation: Self.encapsulation)
      }
    }
  }

  @Test func rejectsAFieldThatNamesAnotherRecord() throws {
    let response = Self.response(
      try Self.responseFields(record: Self.record, secret: Self.secret), profile: .record)
    for other in [
      SpaceMACRecordField(uri: Self.uri + "2", cid: Self.record.cid),
      SpaceMACRecordField(uri: Self.uri, cid: "bafyreib2rxk3rybk3aobmv5cjuql3bm2twh4jo5uxgf5eyqnnzzkx4tcfe"),
    ] {
      #expect(throws: SpaceMACError.fieldMismatch) {
        try SpaceMAC.verifyRecord(response, record: other, encapsulation: Self.encapsulation)
      }
    }
  }

  @Test func hostAnswersOnlyTheRequestedProfile() throws {
    let request = try #require(
      try SpaceMAC.request(
        fromAcceptSignature: SpaceMAC.acceptSignature(profile: .record, keyShare: Self.keyShare),
        profile: .record))
    #expect(throws: SpaceMACError.profileMismatch) {
      try SpaceMAC.responseFields(commit: Self.commit, request: request, sharedSecret: Self.secret)
    }
    #expect(throws: SpaceMACError.malformedHeader) {
      try SpaceMAC.responseFields(
        record: SpaceMACRecordField(uri: Self.uri + "é", cid: Self.record.cid), request: request,
        sharedSecret: Self.secret)
    }
  }

  private static let encapsulation = SpaceKeyEncapsulation(keyShare: keyShare, sharedSecret: secret)

  private static func responseFields(commit: SpaceMACCommitField, secret: SymmetricKey) throws -> [String: String] {
    let request = try #require(
      try SpaceMAC.request(
        fromAcceptSignature: SpaceMAC.acceptSignature(profile: .commit, keyShare: keyShare), profile: .commit))
    return Dictionary(
      uniqueKeysWithValues: try SpaceMAC.responseFields(commit: commit, request: request, sharedSecret: secret)
        .map { ($0.name, $0.value) })
  }

  private static func responseFields(record: SpaceMACRecordField, secret: SymmetricKey) throws -> [String: String] {
    let request = try #require(
      try SpaceMAC.request(
        fromAcceptSignature: SpaceMAC.acceptSignature(profile: .record, keyShare: keyShare), profile: .record))
    return Dictionary(
      uniqueKeysWithValues: try SpaceMAC.responseFields(record: record, request: request, sharedSecret: secret)
        .map { ($0.name, $0.value) })
  }

  private static func response(_ fields: [String: String], profile: SpaceMACProfile) -> SpaceMACResponse {
    SpaceMACResponse(profile: profile) { fields[$0] }
  }

  private static func response(
    _ fields: [(name: String, value: String)], profile: SpaceMACProfile
  ) -> SpaceMACResponse {
    response(Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) }), profile: profile)
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
