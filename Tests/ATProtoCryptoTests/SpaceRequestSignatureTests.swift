import Crypto
import Foundation
import Testing

@testable import ATProtoCrypto

struct SpaceRequestSignatureTests {
  private static let credential = "credential"
  private static let audience = "did:example:repo"

  // MARK: - Use

  // The same authorization and audience as the fixed upstream implementation's
  // tests, so the signature base below is the one a space host rebuilds.
  @Test func useCoversAuthorizationThenAudienceWithTheTag() throws {
    let key = try PrivateKey(type: .p256)
    let signed = try SpaceRequestSignature.use(credential: Self.credential, audience: Self.audience, key: key)

    #expect(signed.authorization == "Atproto-Space-Credential credential")
    #expect(signed.audience == Self.audience)
    #expect(
      signed.signatureInput
        == "atproto-space-credential=(\"authorization\" \"atproto-space-audience\");tag=\"atproto-space-credential\"")
    #expect(
      signed.headerFields.map(\.name) == ["authorization", "atproto-space-audience", "signature-input", "signature"])

    let base = """
      "authorization": Atproto-Space-Credential credential
      "atproto-space-audience": did:example:repo
      "@signature-params": ("authorization" "atproto-space-audience");tag="atproto-space-credential"
      """
    #expect(try key.publicKey.isValidSignature(signature: Self.signatureBytes(signed), for: Data(base.utf8)))
  }

  @Test func signatureDoesNotCoverAChangedField() throws {
    let key = try PrivateKey(type: .p256)
    let signature = try Self.signatureBytes(
      SpaceRequestSignature.use(credential: Self.credential, audience: Self.audience, key: key))

    let changedAudience = """
      "authorization": Atproto-Space-Credential credential
      "atproto-space-audience": did:example:other
      "@signature-params": ("authorization" "atproto-space-audience");tag="atproto-space-credential"
      """
    let changedAuthorization = """
      "authorization": Atproto-Space-Credential other
      "atproto-space-audience": did:example:repo
      "@signature-params": ("authorization" "atproto-space-audience");tag="atproto-space-credential"
      """
    let reordered = """
      "atproto-space-audience": did:example:repo
      "authorization": Atproto-Space-Credential credential
      "@signature-params": ("authorization" "atproto-space-audience");tag="atproto-space-credential"
      """
    for base in [changedAudience, changedAuthorization, reordered] {
      #expect(!key.publicKey.isValidSignature(signature: signature, for: Data(base.utf8)))
    }
  }

  @Test func signatureDoesNotVerifyUnderAnotherKey() throws {
    let signed = try SpaceRequestSignature.use(
      credential: Self.credential, audience: Self.audience, key: PrivateKey(type: .p256))
    let base = """
      "authorization": Atproto-Space-Credential credential
      "atproto-space-audience": did:example:repo
      "@signature-params": ("authorization" "atproto-space-audience");tag="atproto-space-credential"
      """
    let otherKey = try PrivateKey(type: .p256).publicKey
    #expect(try !otherKey.isValidSignature(signature: Self.signatureBytes(signed), for: Data(base.utf8)))
  }

  // MARK: - Signature encoding

  @Test func signatureIsRawNotDER() throws {
    let key = try PrivateKey(type: .p256)
    let signed = try SpaceRequestSignature.use(credential: Self.credential, audience: Self.audience, key: key)
    let raw = try Self.signatureBytes(signed)
    #expect(raw.count == 64)

    // The same signature in DER is what a host must not be sent: it verifies as
    // ECDSA but is not the 64-byte form the field carries.
    let der = try P256.Signing.ECDSASignature(rawRepresentation: raw).derRepresentation
    #expect(der.count != 64)
    let base = """
      "authorization": Atproto-Space-Credential credential
      "atproto-space-audience": did:example:repo
      "@signature-params": ("authorization" "atproto-space-audience");tag="atproto-space-credential"
      """
    #expect(!key.publicKey.isValidSignature(signature: der, for: Data(base.utf8)))
  }

  // MARK: - Rejections

  @Test func rejectsKeysOtherThanP256() throws {
    for type in [KeyType.secp256k1, .ed25519] {
      let key = try PrivateKey(type: type)
      #expect(throws: SpaceRequestSignatureError.unsupportedKeyType) {
        try SpaceRequestSignature.use(credential: Self.credential, audience: Self.audience, key: key)
      }
    }
  }

  @Test func rejectsValuesThatWouldBreakTheHeaderBlock() throws {
    let key = try PrivateKey(type: .p256)
    for value in ["", "   ", "a\r\nb", "a\nb", "a\rb"] {
      #expect(throws: SpaceRequestSignatureError.invalidFieldValue) {
        try SpaceRequestSignature.use(credential: value, audience: Self.audience, key: key)
      }
      #expect(throws: SpaceRequestSignatureError.invalidFieldValue) {
        try SpaceRequestSignature.use(credential: Self.credential, audience: value, key: key)
      }
    }
  }

  @Test func trimsSurroundingWhitespaceBeforeSigning() throws {
    let key = try PrivateKey(type: .p256)
    let signed = try SpaceRequestSignature.use(credential: " credential ", audience: " did:example:repo\t", key: key)
    #expect(signed.authorization == "Atproto-Space-Credential credential")
    #expect(signed.audience == Self.audience)
  }

  @Test func signatureIsPaddedBase64() throws {
    for _ in 0..<8 {
      let signed = try SpaceRequestSignature.use(
        credential: Self.credential, audience: Self.audience, key: PrivateKey(type: .p256))
      let encoded = signed.signature.dropFirst("atproto-space-credential=:".count).dropLast()
      #expect(encoded.count % 4 == 0)
    }
  }

  @Test func descriptionWithholdsTheCredential() throws {
    let signed = try SpaceRequestSignature.use(
      credential: "secret-credential", audience: Self.audience, key: PrivateKey(type: .p256))
    #expect(!signed.description.contains("secret-credential"))
    #expect(!signed.description.contains(signed.signature))
  }
}

extension SpaceRequestSignatureTests {
  /// The bytes of a `signature` field value, `atproto-space-credential=:<base64>:`.
  fileprivate static func signatureBytes(_ signed: SpaceRequestSignature) throws -> Data {
    let prefix = "atproto-space-credential=:"
    #expect(signed.signature.hasPrefix(prefix) && signed.signature.hasSuffix(":"))
    let encoded = signed.signature.dropFirst(prefix.count).dropLast()
    return try #require(Data(base64Encoded: String(encoded)))
  }
}
