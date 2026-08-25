import Foundation
import Testing

@testable import ATProtoCrypto

struct ClientAttestationTests {
  // The worked example in the permissioned data proposal. `iat` and `exp` are
  // pinned so the encoded claims are reproducible.
  private static let clientID = "https://app.example.com/client-metadata.json"
  private static let audience = "did:example:space_did#atproto_space_host"
  private static let issuedAt = Date(timeIntervalSince1970: 1_738_368_000)
  private static let expiresAt = Date(timeIntervalSince1970: 1_738_368_060)
  private static let tokenID = "b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8"

  private func attestation(keyID: String = "key-1") -> ClientAttestation {
    ClientAttestation(
      clientID: Self.clientID,
      audience: Self.audience,
      keyID: keyID,
      issuedAt: Self.issuedAt,
      expiresAt: Self.expiresAt,
      tokenID: Self.tokenID)
  }

  // `KeyType` is not `Sendable`, so these iterate a local list rather than going
  // through `@Test(arguments:)`.
  private var keyTypes: [KeyType] { [.p256, .secp256k1, .ed25519] }

  // MARK: - Claims

  @Test func matchesTheProposalExample() throws {
    let key = try PrivateKey(type: .p256)
    let jwt = try attestation().signed(with: key)

    #expect(try memberNames(of: jwt, 0) == ["alg", "kid", "typ"])
    #expect(
      try header(of: jwt)
        == DecodedHeader(
          typ: "atproto-client-attestation+jwt",
          alg: "ES256",
          kid: "key-1"))

    #expect(try memberNames(of: jwt, 1) == ["aud", "exp", "iat", "iss", "jti", "sub"])
    #expect(
      try payload(of: jwt)
        == DecodedPayload(
          iss: Self.clientID,
          sub: Self.clientID,
          aud: Self.audience,
          iat: 1_738_368_000,
          exp: 1_738_368_060,
          jti: Self.tokenID))
  }

  // A client assertion identifies the client in both claims, so there is no
  // input that can make them disagree.
  @Test func issuerAndSubjectAreBothTheClientID() throws {
    let jwt = try attestation().signed(with: PrivateKey(type: .p256))
    let claims = try payload(of: jwt)
    #expect(claims.iss == Self.clientID)
    #expect(claims.sub == Self.clientID)
  }

  @Test func carriesTheCallersNonceAndExpiry() throws {
    let attestation = ClientAttestation(
      clientID: Self.clientID,
      audience: Self.audience,
      keyID: "key-1",
      issuedAt: Date(timeIntervalSince1970: 1_700_000_000),
      expiresAt: Date(timeIntervalSince1970: 1_700_000_030),
      tokenID: "a-caller-supplied-nonce")
    let claims = try payload(of: attestation.signed(with: PrivateKey(type: .p256)))
    #expect(claims.jti == "a-caller-supplied-nonce")
    #expect(claims.exp == 1_700_000_030)
    #expect(claims.iat == 1_700_000_000)
  }

  // JWT spells `iat` and `exp` as whole seconds, so a `Date` carrying a
  // fractional part has to lose it rather than encode as a decimal.
  @Test func truncatesSubSecondTimestamps() throws {
    let attestation = ClientAttestation(
      clientID: Self.clientID,
      audience: Self.audience,
      keyID: "key-1",
      issuedAt: Date(timeIntervalSince1970: 1_700_000_000.75),
      expiresAt: Date(timeIntervalSince1970: 1_700_000_030.75),
      tokenID: Self.tokenID)
    let claims = try payload(of: attestation.signed(with: PrivateKey(type: .p256)))
    #expect(claims.iat == 1_700_000_000)
    #expect(claims.exp == 1_700_000_030)
  }

  // The `client_id` is a URL, and escaping its slashes would still parse but
  // would not match the bytes any other implementation produces.
  @Test func doesNotEscapeSlashesInTheClientID() throws {
    let jwt = try attestation().signed(with: PrivateKey(type: .p256))
    let segment = try #require(decodedSegment(jwt, 1))
    let json = try #require(String(data: segment, encoding: .utf8))
    #expect(json.contains(Self.clientID))
    #expect(!json.contains("\\/"))
  }

  // MARK: - Algorithms

  @Test func namesTheJOSEAlgorithmForEachKeyType() {
    #expect(KeyType.p256.jwsAlgorithm == "ES256")
    #expect(KeyType.secp256k1.jwsAlgorithm == "ES256K")
    #expect(KeyType.ed25519.jwsAlgorithm == "EdDSA")
  }

  @Test func headerCarriesTheAlgorithmOfTheSigningKey() throws {
    for type in keyTypes {
      let jwt = try attestation().signed(with: PrivateKey(type: type))
      #expect(try header(of: jwt).alg == type.jwsAlgorithm)
    }
  }

  // MARK: - Signature

  @Test func verifiesAgainstTheMatchingPublicKey() throws {
    for type in keyTypes {
      let key = try PrivateKey(type: type)
      let jwt = try attestation().signed(with: key)
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
      let jwt = try attestation().signed(with: PrivateKey(type: type))
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
    let tokenID = ClientAttestation.randomTokenID()
    #expect(tokenID.count == 32)
    #expect(tokenID.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    #expect(tokenID != ClientAttestation.randomTokenID())
  }

  // MARK: - Helpers

  private struct DecodedHeader: Decodable, Equatable {
    let typ: String
    let alg: String
    let kid: String
  }

  private struct DecodedPayload: Decodable, Equatable {
    let iss: String
    let sub: String
    let aud: String
    let iat: Int
    let exp: Int
    let jti: String
  }

  private func header(of jwt: String) throws -> DecodedHeader {
    try JSONDecoder().decode(DecodedHeader.self, from: #require(decodedSegment(jwt, 0)))
  }

  private func payload(of jwt: String) throws -> DecodedPayload {
    try JSONDecoder().decode(DecodedPayload.self, from: #require(decodedSegment(jwt, 1)))
  }
}
