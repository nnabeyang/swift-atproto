#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Why a space request cannot be signed.
///
/// No case carries the credential or any part of it, so an error is safe to
/// log.
public enum SpaceRequestSignatureError: Error, Hashable, Sendable {
  /// The signing key is not ``KeyType/p256``. Space request signatures are
  /// `ecdsa-p256-sha256` only.
  case unsupportedKeyType
  /// A credential or an audience is empty or contains a line break, which
  /// would let it rewrite the header block it is written into.
  case invalidFieldValue
}

/// The HTTP message signature that proves a request presenting a space
/// credential was sent by the holder of the P-256 key the credential is bound
/// to.
///
/// See [RFC 9421](https://www.rfc-editor.org/rfc/rfc9421.html).
///
/// The signature covers `authorization` and `atproto-space-audience`, in that
/// order, under the label `atproto-space-credential` with the parameter
/// `tag="atproto-space-credential"`. It names no key: the credential's
/// `cnf.kid` already does. A space credential is requested with the key in the
/// request body instead, so that request carries no signature.
///
/// Attach every pair in ``headerFields`` to the request. Where the request goes,
/// which audience it names, and how the key is stored are the caller's to
/// decide. See <doc:SpaceRequestSignatures>.
public struct SpaceRequestSignature: Sendable, Hashable {
  /// The authorization scheme that presents a space credential.
  public static let authorizationScheme = "Atproto-Space-Credential"

  /// The label of the signature in `signature-input` and `signature`, and
  /// the value of its `tag` parameter.
  public static let label = "atproto-space-credential"

  /// The `authorization` field value, `Atproto-Space-Credential <credential>`.
  public let authorization: String

  /// The `atproto-space-audience` field value: the DID of the host the request
  /// is addressed to.
  public let audience: String

  /// The `signature-input` field value, labelled `atproto-space-credential`.
  public let signatureInput: String

  /// The `signature` field value: the 64-byte `r` and `s` of the ECDSA
  /// signature, not DER, as a padded base64 byte sequence labelled
  /// `atproto-space-credential`.
  public let signature: String

  /// The fields to attach to the request, in the order they are signed.
  public var headerFields: [(name: String, value: String)] {
    [
      (name: "authorization", value: authorization),
      (name: "atproto-space-audience", value: audience),
      (name: "signature-input", value: signatureInput),
      (name: "signature", value: signature),
    ]
  }

  /// Signs a request that presents `credential` to the host `audience` names.
  ///
  /// Covers `authorization` and then `atproto-space-audience`. `key` has to be
  /// the key the credential is bound to; nothing here can check that, because
  /// the credential is not parsed.
  ///
  /// - Throws: ``SpaceRequestSignatureError/unsupportedKeyType`` when `key` is
  ///   not P-256, ``SpaceRequestSignatureError/invalidFieldValue`` when
  ///   `credential` or `audience` is empty or contains a line break.
  public static func use(credential: String, audience: String, key: PrivateKey) throws -> Self {
    guard key.type == .p256 else { throw SpaceRequestSignatureError.unsupportedKeyType }
    return try Self(
      authorization: "\(authorizationScheme) \(fieldValue(credential))",
      audience: fieldValue(audience),
      key: key)
  }

  private init(authorization: String, audience: String, key: PrivateKey) throws {
    let parameters = "(\"authorization\" \"atproto-space-audience\");tag=\"\(Self.label)\""
    // The signature base of RFC 9421 §2.5: one line per covered component, then
    // the parameters, joined by single line feeds with no trailing one.
    let lines = [
      "\"authorization\": \(authorization)",
      "\"atproto-space-audience\": \(audience)",
      "\"@signature-params\": \(parameters)",
    ]
    let signature = try key.sign(Data(lines.joined(separator: "\n").utf8))

    self.authorization = authorization
    self.audience = audience
    signatureInput = "\(Self.label)=\(parameters)"
    // Foundation writes padded base64, as an RFC 9651 byte sequence requires.
    self.signature = "\(Self.label)=:\(signature.base64EncodedString()):"
  }

  /// `value` with surrounding whitespace removed, as a field value is
  /// canonicalized before it is signed (RFC 9421 §2.1).
  private static func fieldValue(_ value: String) throws -> String {
    guard !value.contains(where: \.isNewline) else {
      throw SpaceRequestSignatureError.invalidFieldValue
    }
    let trimmed = value.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace)
    guard !trimmed.isEmpty else { throw SpaceRequestSignatureError.invalidFieldValue }
    return String(trimmed.reversed())
  }
}

extension SpaceRequestSignature: CustomStringConvertible {
  /// Names the audience and stops there. The reflected description would print
  /// ``authorization``, which carries the credential.
  public var description: String {
    "SpaceRequestSignature(audience: \(audience))"
  }
}
