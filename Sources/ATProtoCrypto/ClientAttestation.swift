#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A short-lived, single-use JWT an application signs with its own key to tell a
/// space authority which application is acting.
///
/// A space authority that gates on client app identity asks for this alongside
/// the delegation token that carries the user's delegation. The two are signed
/// by different parties and evaluated independently: the delegation token says
/// nothing about the application, and this says nothing about the user.
///
/// See <doc:ClientAttestations>.
public struct ClientAttestation: Sendable, Hashable {
  /// The application's `client_id`, the URL its client metadata document is
  /// published at.
  ///
  /// This is written to both `iss` and `sub`, which a client assertion requires
  /// to hold the same value.
  public let clientID: String

  /// How the space host being asked for a credential is addressed, which is its
  /// authority's DID with the `#atproto_space_host` fragment.
  ///
  /// `SwiftAtproto` derives this from a resolved DID document as
  /// `DIDDocument.spaceHostAudience`. It is taken as a string here because
  /// `ATProtoCrypto` does not depend on that module.
  public let audience: String

  /// The `kid` naming the key within the JWKS the application publishes.
  ///
  /// The authority fetches that JWKS to verify the signature, so this has to
  /// name the public half of the key passed to ``signed(with:)``.
  public let keyID: String

  /// When the attestation was issued.
  public let issuedAt: Date

  /// When the attestation stops being accepted.
  ///
  /// An attestation is meant to be short-lived — on the order of a minute.
  public let expiresAt: Date

  /// The `jti` nonce that makes the attestation single-use.
  ///
  /// An authority rejects a repeat, so a value must never be reused across
  /// attestations. ``randomTokenID()`` produces a suitable one.
  public let tokenID: String

  /// Describes an attestation. Nothing is signed until ``signed(with:)``.
  ///
  /// Every claim is supplied by the caller, including the two that a general
  /// purpose JWT library would fill in on its own: an attestation is short-lived
  /// and single-use, so its lifetime and its nonce are the caller's to control.
  public init(
    clientID: String,
    audience: String,
    keyID: String,
    issuedAt: Date,
    expiresAt: Date,
    tokenID: String
  ) {
    self.clientID = clientID
    self.audience = audience
    self.keyID = keyID
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.tokenID = tokenID
  }

  /// Signs the attestation with `key`, returning it as a compact JWS.
  ///
  /// ``keyID`` has to name `key`'s public half in the JWKS the application
  /// publishes; that pairing is not checked here, because this module has no way
  /// to see the JWKS.
  ///
  /// ``issuedAt`` and ``expiresAt`` become `iat` and `exp`, which JWT spells as
  /// whole seconds since the Unix epoch, so any sub-second part is truncated.
  ///
  /// - Throws: whatever ``PrivateKey/sign(_:)`` throws for `key`'s type.
  public func signed(with key: PrivateKey) throws -> String {
    try compactJWS(
      header: Header(alg: key.type.jwsAlgorithm, kid: keyID),
      payload: Payload(
        aud: audience,
        exp: Int(expiresAt.timeIntervalSince1970),
        iat: Int(issuedAt.timeIntervalSince1970),
        iss: clientID,
        jti: tokenID,
        sub: clientID),
      signedWith: key)
  }

  /// A fresh `jti`: 16 random bytes as lowercase hexadecimal.
  ///
  /// Each attestation needs its own, so call this once per attestation rather
  /// than holding onto a value.
  public static func randomTokenID() -> String {
    var generator = SystemRandomNumberGenerator()
    let digits = "0123456789abcdef"
    var hex = ""
    hex.reserveCapacity(32)
    for _ in 0..<16 {
      let byte: UInt8 = generator.next()
      hex.append(digits[digits.index(digits.startIndex, offsetBy: Int(byte >> 4))])
      hex.append(digits[digits.index(digits.startIndex, offsetBy: Int(byte & 0x0F))])
    }
    return hex
  }

  private struct Header: Encodable {
    // Fixed by the proposal: the same shape as an OAuth client assertion, but
    // typed so that a space host cannot be handed one addressed elsewhere.
    let typ = "atproto-client-attestation+jwt"
    let alg: String
    let kid: String
  }

  private struct Payload: Encodable {
    let aud: String
    let exp: Int
    let iat: Int
    let iss: String
    let jti: String
    let sub: String
  }
}
