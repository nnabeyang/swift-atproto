import Foundation
import Testing

@testable import ATProtoCrypto

struct DPoPProofTests {
  private static let url = URL(string: "https://repo.example.com/xrpc/com.atproto.repo.getRecord")!
  private static let issuedAt = Date(timeIntervalSince1970: 1_738_368_000)
  private static let tokenID = "b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8"

  // An opaque stand-in for a space credential; only its digest is ever encoded.
  // The expected `ath` is `base64url(SHA-256(utf8(credential)))`, computed
  // independently of this module.
  private static let credential = "a-space-credential-jwt"
  private static let credentialHash = "bks-F6oDLcO-nvmRslqy5tPdSGUG6sxi-WTRDYCG1Pc"

  private func proof(
    httpMethod: String = "GET",
    url: URL = DPoPProofTests.url,
    credential: String? = nil
  ) -> DPoPProof {
    DPoPProof(
      httpMethod: httpMethod,
      url: url,
      issuedAt: Self.issuedAt,
      tokenID: Self.tokenID,
      credential: credential)
  }

  // `KeyType` is not `Sendable`, so these iterate a local list rather than going
  // through `@Test(arguments:)`.
  private var keyTypes: [KeyType] { [.p256, .secp256k1, .ed25519] }

  // MARK: - Claims

  @Test func carriesTheMemberSetRFC9449Prescribes() throws {
    let jwt = try proof().signed(with: PrivateKey(type: .p256))

    #expect(try memberNames(of: jwt, 0) == ["alg", "jwk", "typ"])
    #expect(try header(of: jwt).typ == "dpop+jwt")
    #expect(try header(of: jwt).alg == "ES256")

    // No `exp` — a proof is bounded by its `iat` — and no `nonce`, which the
    // space exchange does not use.
    #expect(try memberNames(of: jwt, 1) == ["htm", "htu", "iat", "jti"])
    let claims = try payload(of: jwt)
    #expect(claims.htm == "GET")
    #expect(claims.htu == "https://repo.example.com/xrpc/com.atproto.repo.getRecord")
    #expect(claims.iat == 1_738_368_000)
    #expect(claims.jti == Self.tokenID)
    #expect(claims.ath == nil)
  }

  @Test func carriesTheCallersMethod() throws {
    let jwt = try proof(httpMethod: "POST").signed(with: PrivateKey(type: .p256))
    #expect(try payload(of: jwt).htm == "POST")
  }

  // JWT spells `iat` as whole seconds, so a `Date` carrying a fractional part
  // has to lose it rather than encode as a decimal.
  @Test func truncatesSubSecondTimestamps() throws {
    let proof = DPoPProof(
      httpMethod: "GET",
      url: Self.url,
      issuedAt: Date(timeIntervalSince1970: 1_700_000_000.75),
      tokenID: Self.tokenID)
    #expect(try payload(of: proof.signed(with: PrivateKey(type: .p256))).iat == 1_700_000_000)
  }

  // MARK: - Credential binding

  // The exchange that obtains a credential has none to hash yet, and a verifier
  // rejects a proof that carries `ath` anyway.
  @Test func omitsAthWhenObtainingACredential() throws {
    let jwt = try proof().signed(with: PrivateKey(type: .p256))
    #expect(!(try memberNames(of: jwt, 1).contains("ath")))
  }

  @Test func hashesTheCredentialIntoAth() throws {
    let jwt = try proof(credential: Self.credential).signed(with: PrivateKey(type: .p256))
    #expect(try memberNames(of: jwt, 1) == ["ath", "htm", "htu", "iat", "jti"])
    #expect(try payload(of: jwt).ath == Self.credentialHash)
  }

  // `ath` is a digest, so the credential itself must not survive anywhere in the
  // proof — nor in the description a holder is most likely to log.
  @Test func withholdsTheCredentialAndTheNonce() throws {
    let proof = proof(credential: Self.credential)
    let jwt = try proof.signed(with: PrivateKey(type: .p256))
    #expect(!jwt.contains(Self.credential))
    #expect(!proof.description.contains(Self.credential))
    #expect(!proof.description.contains(Self.tokenID))
    #expect(proof.description.contains("presentsCredential: true"))
  }

  // MARK: - Target URI

  // RFC 9449 §4.2. An XRPC query carries its parameters in the query string, so
  // a proof that kept them would never match what the verifier computes.
  @Test func dropsTheQueryAndFragmentFromTheTargetURI() throws {
    let url = URL(string: "https://repo.example.com/xrpc/com.atproto.repo.getRecord?rkey=self#f")!
    #expect(try proof(url: url).httpTargetURI == Self.url.absoluteString)
  }

  @Test func suppliesARootPathForABareOrigin() throws {
    let url = URL(string: "https://repo.example.com")!
    #expect(try proof(url: url).httpTargetURI == "https://repo.example.com/")
  }

  @Test func dropsADefaultPortAndKeepsAnyOther() throws {
    #expect(
      try proof(url: URL(string: "https://repo.example.com:443/xrpc/a")!).httpTargetURI
        == "https://repo.example.com/xrpc/a")
    #expect(
      try proof(url: URL(string: "http://repo.example.com:80/xrpc/a")!).httpTargetURI
        == "http://repo.example.com/xrpc/a")
    #expect(
      try proof(url: URL(string: "https://repo.example.com:8443/xrpc/a")!).httpTargetURI
        == "https://repo.example.com:8443/xrpc/a")
  }

  // The verifier derives its side from a parsed URL, which normalizes both.
  @Test func lowercasesTheSchemeAndHost() throws {
    let url = URL(string: "HTTPS://Repo.Example.COM/xrpc/a")!
    #expect(try proof(url: url).httpTargetURI == "https://repo.example.com/xrpc/a")
  }

  @Test func rejectsAURLWithNoOrigin() throws {
    #expect(throws: DPoPProofError.unsupportedTargetURL) {
      try proof(url: URL(string: "mailto:someone@example.com")!).httpTargetURI
    }
    #expect(throws: DPoPProofError.unsupportedTargetURL) {
      try proof(url: URL(string: "/xrpc/a")!).signed(with: PrivateKey(type: .p256))
    }
  }

  // An `htu` is a URL, and escaping its slashes would still parse but would not
  // match the bytes any other implementation produces.
  @Test func doesNotEscapeSlashesInTheTargetURI() throws {
    let jwt = try proof().signed(with: PrivateKey(type: .p256))
    let segment = try #require(decodedSegment(jwt, 1))
    let json = try #require(String(data: segment, encoding: .utf8))
    #expect(json.contains(Self.url.absoluteString))
    #expect(!json.contains("\\/"))
  }

  // MARK: - Embedded key

  // A verifier checks the signature against the proof's own `jwk`, so the header
  // has to carry the public key — and nothing beyond the members a thumbprint is
  // taken over.
  @Test func embedsTheBarePublicKey() throws {
    for type in keyTypes {
      let jwt = try proof().signed(with: PrivateKey(type: type))
      let jwk = try header(of: jwt).jwk
      switch type {
      case .p256:
        #expect(jwk.crv == "P-256")
        #expect(jwk.kty == "EC")
        #expect(jwk.y != nil)
      case .secp256k1:
        #expect(jwk.crv == "secp256k1")
        #expect(jwk.kty == "EC")
        #expect(jwk.y != nil)
      case .ed25519:
        #expect(jwk.crv == "Ed25519")
        #expect(jwk.kty == "OKP")
        #expect(jwk.y == nil)
      }
      let expected = jwk.y == nil ? ["crv", "kty", "x"] : ["crv", "kty", "x", "y"]
      #expect(try jwkMemberNames(of: jwt) == expected)
    }
  }

  // The private half must never reach the wire, whatever the member set check
  // above happens to name.
  @Test func neverEmbedsPrivateMaterial() throws {
    for type in keyTypes {
      let key = try PrivateKey(type: type)
      let jwt = try proof().signed(with: key)
      let segment = try #require(decodedSegment(jwt, 0))
      let json = try #require(String(data: segment, encoding: .utf8))
      #expect(!json.contains("\"d\""))
      #expect(!json.contains(base64URLEncoded(key.rawRepresentation)))
    }
  }

  // The credential names its key by thumbprint in `cnf.jkt`, so the key the
  // proof embeds has to hash to the same value.
  @Test func embeddedKeyMatchesTheThumbprintOfTheSigningKey() throws {
    for type in keyTypes {
      let key = try PrivateKey(type: type)
      let jwt = try proof().signed(with: key)
      let jwk = try header(of: jwt).jwk
      var members: [(name: String, value: String)] = [
        ("crv", jwk.crv), ("kty", jwk.kty), ("x", jwk.x),
      ]
      if let y = jwk.y {
        members.append(("y", y))
      }
      #expect(try PublicKey.thumbprint(members: members) == key.publicKey.jwkThumbprint)
    }
  }

  @Test func headerCarriesTheAlgorithmOfTheSigningKey() throws {
    for type in keyTypes {
      let jwt = try proof().signed(with: PrivateKey(type: type))
      #expect(try header(of: jwt).alg == type.jwsAlgorithm)
    }
  }

  // MARK: - Signature

  @Test func verifiesAgainstTheEmbeddedKey() throws {
    for type in keyTypes {
      let key = try PrivateKey(type: type)
      let jwt = try proof(credential: Self.credential).signed(with: key)
      let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
      let signingInput = Data(segments[0..<2].joined(separator: ".").utf8)
      let signature = try #require(decodedSegment(jwt, 2))
      #expect(key.publicKey.isValidSignature(signature: signature, for: signingInput))

      let other = try PrivateKey(type: type).publicKey
      #expect(!other.isValidSignature(signature: signature, for: signingInput))
    }
  }

  @Test func isThreeUnpaddedBase64URLSegments() throws {
    for type in keyTypes {
      let jwt = try proof(credential: Self.credential).signed(with: PrivateKey(type: type))
      let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
      #expect(segments.count == 3)
      #expect(segments.allSatisfy { !$0.isEmpty })
      #expect(!jwt.contains("+"))
      #expect(!jwt.contains("/"))
      #expect(!jwt.contains("="))
    }
  }

  // MARK: - Nonces

  @Test func randomTokenIDIsHexAndDoesNotRepeat() {
    let tokenID = DPoPProof.randomTokenID()
    #expect(tokenID.count == 32)
    #expect(tokenID.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    #expect(tokenID != DPoPProof.randomTokenID())
  }

  // MARK: - Helpers

  private struct DecodedJWK: Decodable, Equatable {
    let crv: String
    let kty: String
    let x: String
    let y: String?
  }

  private struct DecodedHeader: Decodable, Equatable {
    let typ: String
    let alg: String
    let jwk: DecodedJWK
  }

  private struct DecodedPayload: Decodable, Equatable {
    let ath: String?
    let htm: String
    let htu: String
    let iat: Int
    let jti: String
  }

  private func header(of jwt: String) throws -> DecodedHeader {
    try JSONDecoder().decode(DecodedHeader.self, from: #require(decodedSegment(jwt, 0)))
  }

  private func payload(of jwt: String) throws -> DecodedPayload {
    try JSONDecoder().decode(DecodedPayload.self, from: #require(decodedSegment(jwt, 1)))
  }

  // `memberNames(of:_:)` reads a whole segment; the `jwk` member set is a level
  // down, so it is unwrapped here first.
  private struct JWKMemberNames: Decodable {
    let jwk: [String: String]
  }

  private func jwkMemberNames(of jwt: String) throws -> [String] {
    try JSONDecoder()
      .decode(JWKMemberNames.self, from: #require(decodedSegment(jwt, 0)))
      .jwk.keys.sorted()
  }
}
