import Foundation
import Testing

@testable import SwiftAtproto

// Introspection reads a token; it never verifies one. Every fixture here therefore carries a
// signature segment that is only shaped like a signature.
struct SpaceTokenIntrospectionTests {
  static let spaceDID = "did:plc:ewvi7nxzyoun6zhxrhs64oiz"
  // The proposal writes this space type as `com.example.space_type`, which is not an NSID — a name
  // segment admits no underscore — so the fixture uses the space ref the other tests in this
  // target share.
  static let spaceRef = "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/self"
  static let otherSpaceRef = "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/other"
  static let thumbprint = "0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I"
  static let clientID = "https://app.example.com/client-metadata.json"
  static let spaceHost = "did:plc:ewvi7nxzyoun6zhxrhs64oiz#atproto_space_host"
  static let nonce = "9f8e7d6c5b4a3210fedcba9876543210"
  static let issuedAt = Date(timeIntervalSince1970: 1_738_368_000)
  static let expiresAt = Date(timeIntervalSince1970: 1_738_375_200)

  // Raw string literals with `##` delimiters: the JSON carries `"#`, which would close a `#"`
  // literal early.
  static let credentialHeader = ##"""
    {"typ":"atproto-space-credential+jwt","alg":"ES256K","kid":"#atproto_space"}
    """##

  static let credentialPayload = ##"""
    {"iss":"\##(spaceDID)","sub":"\##(spaceRef)","cnf":{"jkt":"\##(thumbprint)"},\##
    "iat":1738368000,"exp":1738375200,"jti":"\##(nonce)"}
    """##

  static let delegationHeader = ##"""
    {"typ":"atproto-space-delegation+jwt","alg":"ES256K","kid":"#atproto"}
    """##

  static let delegationPayload = ##"""
    {"iss":"did:plc:44ybard66vv44zksje25o7dz","sub":"\##(spaceRef)","aud":"\##(spaceHost)",\##
    "iat":1738368000,"exp":1738375200,"jti":"\##(nonce)"}
    """##

  static let attestationHeader = ##"""
    {"typ":"atproto-client-attestation+jwt","alg":"ES256","kid":"key-1"}
    """##

  static let attestationPayload = ##"""
    {"iss":"\##(clientID)","sub":"\##(clientID)","aud":"\##(spaceHost)",\##
    "iat":1738368000,"exp":1738375200,"jti":"\##(nonce)"}
    """##

  // MARK: - Structure

  @Test func rejectsATokenThatIsNotThreeSegments() {
    for jwt in ["", "abc", "\(Self.encoded(Self.credentialHeader)).\(Self.encoded(Self.credentialPayload))", "a.b.c.d"] {
      #expect(throws: SpaceTokenError.malformed) {
        try UnverifiedSpaceCredential(introspecting: jwt)
      }
    }
  }

  @Test func rejectsASegmentThatIsNotUnpaddedURLSafeBase64() {
    let payload = Self.encoded(Self.credentialPayload)
    // The standard alphabet, padding, and a character outside both alphabets.
    for header in ["ab+c", "ab/c", "\(Self.encoded(Self.credentialHeader))==", "ab c"] {
      #expect(throws: SpaceTokenError.malformed) {
        try UnverifiedSpaceCredential(introspecting: "\(header).\(payload).c2ln")
      }
    }
  }

  @Test func rejectsAnEmptySignatureSegment() {
    let jwt = "\(Self.encoded(Self.credentialHeader)).\(Self.encoded(Self.credentialPayload))."
    #expect(throws: SpaceTokenError.malformed) {
      try UnverifiedSpaceCredential(introspecting: jwt)
    }
  }

  @Test func rejectsASegmentThatIsNotJSON() {
    #expect(throws: SpaceTokenError.malformed) {
      try UnverifiedSpaceCredential(introspecting: Self.token(header: "not json", payload: Self.credentialPayload))
    }
    #expect(throws: SpaceTokenError.malformed) {
      try UnverifiedSpaceCredential(introspecting: Self.token(header: Self.credentialHeader, payload: "[]"))
    }
  }

  @Test func rejectsAnotherCredentialClass() {
    let jwt = Self.token(header: Self.delegationHeader, payload: Self.delegationPayload)
    #expect(
      throws: SpaceTokenError.wrongType(
        expected: "atproto-space-credential+jwt", found: "atproto-space-delegation+jwt")
    ) {
      try UnverifiedSpaceCredential(introspecting: jwt)
    }
  }

  // MARK: - Required claims

  @Test func requiresAlgIssSubAndExp() {
    let cases: [(String, String, String)] = [
      ("alg", ##"{"typ":"atproto-space-credential+jwt"}"##, Self.credentialPayload),
      ("iss", Self.credentialHeader, Self.credentialPayload(dropping: "iss")),
      ("sub", Self.credentialHeader, Self.credentialPayload(dropping: "sub")),
      ("exp", Self.credentialHeader, Self.credentialPayload(dropping: "exp")),
    ]
    for (claim, header, payload) in cases {
      #expect(throws: SpaceTokenError.missingClaim(claim)) {
        try UnverifiedSpaceCredential(introspecting: Self.token(header: header, payload: payload))
      }
    }
  }

  @Test func requiresTheBoundKeyOnACredential() {
    let payload = Self.credentialPayload(dropping: "cnf")
    #expect(throws: SpaceTokenError.missingClaim("cnf.jkt")) {
      try UnverifiedSpaceCredential(
        introspecting: Self.token(header: Self.credentialHeader, payload: payload))
    }
  }

  @Test func acceptsACredentialWithoutATokenID() throws {
    // A credential is reused across every repo host serving the space, so it needs no replay nonce.
    let payload = Self.credentialPayload(dropping: "jti")
    let credential = try UnverifiedSpaceCredential(
      introspecting: Self.token(header: Self.credentialHeader, payload: payload))
    #expect(credential.tokenID == nil)
  }

  @Test func requiresAnAudienceAndATokenIDOnADelegationToken() {
    for claim in ["aud", "jti"] {
      let payload = Self.delegationPayload(dropping: claim)
      #expect(throws: SpaceTokenError.missingClaim(claim)) {
        try UnverifiedSpaceDelegationToken(
          introspecting: Self.token(header: Self.delegationHeader, payload: payload))
      }
    }
  }

  @Test func requiresAnAudienceAndATokenIDOnAClientAttestation() {
    for claim in ["aud", "jti"] {
      let payload = Self.attestationPayload(dropping: claim)
      #expect(throws: SpaceTokenError.missingClaim(claim)) {
        try UnverifiedClientAttestation(
          introspecting: Self.token(header: Self.attestationHeader, payload: payload))
      }
    }
  }

  // MARK: - Typed claims

  @Test func readsEveryClaimOfASpaceCredential() throws {
    let credential = try UnverifiedSpaceCredential(
      introspecting: Self.token(header: Self.credentialHeader, payload: Self.credentialPayload))
    #expect(credential.issuer.rawValue == Self.spaceDID)
    #expect(credential.space.rawValue == Self.spaceRef)
    #expect(credential.space.skey.rawValue == "self")
    #expect(credential.boundKeyThumbprint == Self.thumbprint)
    #expect(credential.issuedAt == Self.issuedAt)
    #expect(credential.expiresAt == Self.expiresAt)
    #expect(credential.tokenID == Self.nonce)
    #expect(credential.algorithm == "ES256K")
    // The `kid` is what `DIDDocument.spaceSigningKey(keyId:)` takes.
    #expect(credential.keyID == "#atproto_space")
  }

  @Test func readsADelegationToken() throws {
    let token = try UnverifiedSpaceDelegationToken(
      introspecting: Self.token(header: Self.delegationHeader, payload: Self.delegationPayload))
    #expect(token.issuer.rawValue == "did:plc:44ybard66vv44zksje25o7dz")
    #expect(token.space.rawValue == Self.spaceRef)
    #expect(token.audience.did.rawValue == Self.spaceDID)
    #expect(token.audience.fragment == "atproto_space_host")
    #expect(token.tokenID == Self.nonce)
  }

  @Test func rejectsASubjectThatIsNotASpaceRef() {
    // A record URI within a space is not the space itself.
    let payload = Self.credentialPayload(
      replacing: "sub", with: "at://\(Self.spaceDID)/app.bsky.feed.post/3jui7kd54zh2y")
    #expect(throws: LexiconStringFormatError.self) {
      try UnverifiedSpaceCredential(
        introspecting: Self.token(header: Self.credentialHeader, payload: payload))
    }
  }

  @Test func rejectsAnIssuerThatIsNotADID() {
    let payload = Self.credentialPayload(replacing: "iss", with: "alice.example.com")
    #expect(throws: LexiconStringFormatError.self) {
      try UnverifiedSpaceCredential(
        introspecting: Self.token(header: Self.credentialHeader, payload: payload))
    }
  }

  @Test func rejectsAnAudienceThatIsNotAServiceIdentifier() {
    let payload = Self.delegationPayload(replacing: "aud", with: "\(Self.spaceDID)#")
    #expect(throws: DIDDocument.VerifyError.self) {
      try UnverifiedSpaceDelegationToken(
        introspecting: Self.token(header: Self.delegationHeader, payload: payload))
    }
  }

  @Test func acceptsAHeaderWithoutAKeyID() throws {
    let header = ##"{"typ":"atproto-space-credential+jwt","alg":"ES256K"}"##
    let credential = try UnverifiedSpaceCredential(
      introspecting: Self.token(header: header, payload: Self.credentialPayload))
    #expect(credential.keyID == nil)
  }

  // MARK: - Client attestation

  @Test func readsAClientAttestation() throws {
    let attestation = try UnverifiedClientAttestation(
      introspecting: Self.token(header: Self.attestationHeader, payload: Self.attestationPayload))
    #expect(attestation.clientID == Self.clientID)
    #expect(attestation.audience.rawValue == Self.spaceHost)
    #expect(attestation.algorithm == "ES256")
    #expect(attestation.keyID == "key-1")
    #expect(attestation.tokenID == Self.nonce)
  }

  @Test func rejectsAClientAttestationWhoseIssuerAndSubjectDisagree() {
    let payload = Self.attestationPayload(
      replacing: "sub", with: "https://other.example.com/client-metadata.json")
    #expect(throws: SpaceTokenError.clientIDMismatch) {
      try UnverifiedClientAttestation(
        introspecting: Self.token(header: Self.attestationHeader, payload: payload))
    }
  }

  @Test func readsAnAttestationSignedByATProtoCrypto() throws {
    // Recorded from `ATProtoCrypto.ClientAttestation.signed(with:)`. This target does not depend on
    // that module, so a recorded token is the only way to hold the two sides to one wire format.
    let jwt = """
      eyJhbGciOiJFUzI1NiIsImtpZCI6ImtleS0xIiwidHlwIjoiYXRwcm90by1jbGllbnQtYXR0ZXN0YXRpb24rand0In0\
      .eyJhdWQiOiJkaWQ6cGxjOmV3dmk3bnh6eW91bjZ6aHhyaHM2NG9peiNhdHByb3RvX3NwYWNlX2hvc3QiLCJleHAiOjE\
      3MzgzNjgwNjAsImlhdCI6MTczODM2ODAwMCwiaXNzIjoiaHR0cHM6Ly9hcHAuZXhhbXBsZS5jb20vY2xpZW50LW1ldGF\
      kYXRhLmpzb24iLCJqdGkiOiJiM2M0ZDVlNmY3YThiOWMwZDFlMmYzYTRiNWM2ZDdlOCIsInN1YiI6Imh0dHBzOi8vYXB\
      wLmV4YW1wbGUuY29tL2NsaWVudC1tZXRhZGF0YS5qc29uIn0\
      .P9qkLdP-Qyl5v7lt47puZeMBfRDLcDEyVX5Fyrno9mJoCqZuMh4k_A3wW6rjB50h9BqZl6BDi6xZce4qma88rg
      """
    let attestation = try UnverifiedClientAttestation(introspecting: jwt)
    #expect(attestation.clientID == Self.clientID)
    #expect(attestation.audience.rawValue == Self.spaceHost)
    #expect(attestation.tokenID == "b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8")
    #expect(attestation.issuedAt == Date(timeIntervalSince1970: 1_738_368_000))
    #expect(attestation.expiresAt == Date(timeIntervalSince1970: 1_738_368_060))
    #expect(attestation.algorithm == "ES256")
    #expect(attestation.keyID == "key-1")
  }

  // MARK: - Credential checks

  @Test func reportsExpiryWithTheDefaultClockSkew() throws {
    let credential = try Self.credential()
    #expect(!credential.isExpired(at: Self.expiresAt))
    // The default skew is permissive: the credential still counts as live for five seconds past
    // `exp`, and not one second longer.
    #expect(!credential.isExpired(at: Self.expiresAt.addingTimeInterval(4)))
    #expect(credential.isExpired(at: Self.expiresAt.addingTimeInterval(5)))
  }

  @Test func reportsExpiryWithAnExplicitClockSkew() throws {
    let credential = try Self.credential()
    #expect(credential.isExpired(at: Self.expiresAt, clockSkew: 0))
    // A holder that wants to renew early asks for the window to close early.
    #expect(credential.isExpired(at: Self.expiresAt.addingTimeInterval(-60), clockSkew: -120))
  }

  @Test func authorizesOnlyTheSpaceItNames() throws {
    let credential = try Self.credential()
    #expect(credential.authorizes(try SpaceRef(string: Self.spaceRef)))
    #expect(!credential.authorizes(try SpaceRef(string: Self.otherSpaceRef)))
  }

  @Test func isBoundOnlyToItsOwnKeyThumbprint() throws {
    let credential = try Self.credential()
    #expect(credential.isBound(toKeyThumbprint: Self.thumbprint))
    // A thumbprint is base64url, so the comparison is case-sensitive.
    #expect(!credential.isBound(toKeyThumbprint: Self.thumbprint.lowercased()))
    #expect(!credential.isBound(toKeyThumbprint: "not-the-same-key"))
  }

  // MARK: - Redaction

  @Test func descriptionsWithholdNoncesAndThumbprints() throws {
    let credential = try Self.credential()
    let delegation = try UnverifiedSpaceDelegationToken(
      introspecting: Self.token(header: Self.delegationHeader, payload: Self.delegationPayload))
    let attestation = try UnverifiedClientAttestation(
      introspecting: Self.token(header: Self.attestationHeader, payload: Self.attestationPayload))

    for description in [credential.description, delegation.description, attestation.description] {
      #expect(!description.contains(Self.nonce))
      #expect(!description.contains(Self.thumbprint))
    }
    #expect(credential.description.contains(Self.spaceRef))
  }

}

// MARK: - Fixtures

extension SpaceTokenIntrospectionTests {
  static func encoded(_ json: String) -> String {
    Data(json.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func token(header: String, payload: String) -> String {
    "\(encoded(header)).\(encoded(payload)).c2lnbmF0dXJl"
  }

  static func credential() throws -> UnverifiedSpaceCredential {
    try UnverifiedSpaceCredential(introspecting: token(header: credentialHeader, payload: credentialPayload))
  }

  /// Rewrites a payload by round-tripping it through `JSONSerialization`, so that a test can name
  /// the claim it is interested in instead of restating the whole object.
  private static func rewrite(_ payload: String, _ transform: (inout [String: Any]) -> Void) -> String {
    var object = try! JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
    transform(&object)
    return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
  }

  static func credentialPayload(dropping claim: String) -> String {
    rewrite(credentialPayload) { $0[claim] = nil }
  }

  static func credentialPayload(replacing claim: String, with value: String) -> String {
    rewrite(credentialPayload) { $0[claim] = value }
  }

  static func delegationPayload(dropping claim: String) -> String {
    rewrite(delegationPayload) { $0[claim] = nil }
  }

  static func delegationPayload(replacing claim: String, with value: String) -> String {
    rewrite(delegationPayload) { $0[claim] = value }
  }

  static func attestationPayload(dropping claim: String) -> String {
    rewrite(attestationPayload) { $0[claim] = nil }
  }

  static func attestationPayload(replacing claim: String, with value: String) -> String {
    rewrite(attestationPayload) { $0[claim] = value }
  }
}
