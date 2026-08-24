import Crypto

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

extension PublicKey {
  /// The RFC 7638 JWK thumbprint of this key, base64url-encoded without padding.
  ///
  /// This is the value a `cnf.jkt` claim carries: comparing it against the
  /// thumbprint of a key you hold tells you whether a token was bound to that
  /// key. It is a digest of the key material alone, so two representations of
  /// the same key — a compressed and an uncompressed `secp256k1` point, say —
  /// produce the same thumbprint.
  ///
  /// - Throws: `secp256k1Error.underlyingCryptoError` when a `secp256k1` point
  ///   cannot be re-serialized to read its coordinates.
  public var jwkThumbprint: String {
    get throws {
      switch raw {
      case .p256:
        // `rawRepresentation` is the two 32-byte coordinates, `x` then `y`.
        let bytes = rawBytes
        return Self.thumbprint(
          members: [
            ("crv", "P-256"),
            ("kty", "EC"),
            ("x", base64URLEncoded(bytes.prefix(32))),
            ("y", base64URLEncoded(bytes.suffix(32))),
          ])
      case .secp256k1(let key):
        // Drop the `0x04` prefix of the uncompressed encoding.
        let bytes = try key.uncompressedBytes.dropFirst()
        return Self.thumbprint(
          members: [
            ("crv", "secp256k1"),
            ("kty", "EC"),
            ("x", base64URLEncoded(bytes.prefix(32))),
            ("y", base64URLEncoded(bytes.suffix(32))),
          ])
      case .ed25519:
        return Self.thumbprint(
          members: [
            ("crv", "Ed25519"),
            ("kty", "OKP"),
            ("x", base64URLEncoded(rawBytes)),
          ])
      }
    }
  }

  // RFC 7638 §3: serialize the required members, and only those, as JSON with no
  // whitespace and the member names in lexicographic order, then take the
  // base64url-encoded SHA-256 of those octets.
  //
  // `members` is taken in order rather than sorted here so that a caller states
  // the order the RFC prescribes for its key type; the tests pass the RFC's own
  // worked example through this. Every value the AT Protocol key types produce is
  // base64url or a curve name, so no value needs JSON string escaping.
  static func thumbprint(members: [(name: String, value: String)]) -> String {
    let json = members.map { #""\#($0.name)":"\#($0.value)""# }.joined(separator: ",")
    let digest = SHA256.hash(data: Data("{\(json)}".utf8))
    return base64URLEncoded(Data(digest))
  }
}

/// Encodes `data` with the URL-safe base64 alphabet and no padding, as every
/// JOSE field is spelled.
///
/// `Multibase` also encodes base64url, but prefixes the result with the
/// multibase tag, which a JOSE field must not carry.
func base64URLEncoded(_ data: some DataProtocol) -> String {
  var encoded = ""
  encoded.reserveCapacity(((data.count + 2) / 3) * 4)
  for character in Data(data).base64EncodedString() {
    switch character {
    case "+": encoded.append("-")
    case "/": encoded.append("_")
    case "=": break
    default: encoded.append(character)
    }
  }
  return encoded
}
