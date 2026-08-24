#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

extension KeyType {
  /// The JOSE algorithm identifier for this key type, as a JWS header spells it
  /// in its `alg` member.
  ///
  /// `secp256k1` is `ES256K` (RFC 8812) rather than the `ES256` that names the
  /// P-256 curve, so the two ECDSA cases are not interchangeable even though
  /// both hash with SHA-256 and both produce a 64-byte signature.
  public var jwsAlgorithm: String {
    switch self {
    case .secp256k1: "ES256K"
    case .p256: "ES256"
    case .ed25519: "EdDSA"
    }
  }
}

/// Serializes `header` and `payload` as a compact JWS signed with `key`.
///
/// The result is the three base64url segments JOSE prescribes, joined by dots.
func compactJWS(
  header: some Encodable,
  payload: some Encodable,
  signedWith key: PrivateKey
) throws -> String {
  let encoder = JSONEncoder()
  // A `client_id` is a URL, and the default escapes every `/` in it as `\/`.
  // That is legal JSON, but it makes the encoded segment differ from what every
  // other implementation emits for the same claims. Sorting the keys is not
  // required — a JWS member set is unordered — but it makes the segments
  // reproducible for a given set of claims.
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

  let signingInput =
    "\(base64URLEncoded(try encoder.encode(header))).\(base64URLEncoded(try encoder.encode(payload)))"

  // `PrivateKey.sign(_:)` already returns what JWS asks for on all three key
  // types: the two ECDSA cases hash with SHA-256 internally and return the
  // 64-byte `r‖s` concatenation that ES256 and ES256K require, and Ed25519
  // signs the message directly as EdDSA does. No re-encoding is needed here.
  let signature = try key.sign(Data(signingInput.utf8))
  return "\(signingInput).\(base64URLEncoded(signature))"
}
