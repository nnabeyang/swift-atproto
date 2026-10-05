#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Why a space request cannot be signed.
///
/// No case carries the token, the credential, or any part of them, so an error
/// is safe to log.
public enum SpaceRequestSignatureError: Error, Hashable, Sendable {
  /// The signing key is not ``KeyType/p256``. Space request signatures are
  /// `ecdsa-p256-sha256` only.
  case unsupportedKeyType
  /// A token, a credential, or an audience is empty or contains a line break,
  /// which would let it rewrite the header block it is written into.
  case invalidFieldValue
}

/// The HTTP message signature that proves a space request was sent by the holder
/// of a P-256 key.
///
/// See [RFC 9421](https://www.rfc-editor.org/rfc/rfc9421.html).
///
/// Two requests carry one. The exchange that trades a delegation token for a
/// space credential signs only `authorization` and names the key in `keyid`, so
/// the issued credential can be bound to it. Every request that presents the
/// credential afterwards signs `authorization` and `atproto-space-audience`, in
/// that order, and names no key: the credential's `cnf.kid` already does.
///
/// Attach every pair in ``headerFields`` to the request. Where the request goes,
/// which audience it names, and how the key is stored are the caller's to
/// decide. See <doc:SpaceRequestSignatures>.
public struct SpaceRequestSignature: Sendable, Hashable {
  /// The `authorization` field value: `Bearer <delegation token>` for the
  /// exchange, `Atproto-Space <credential>` afterwards.
  public let authorization: String

  /// The `atproto-space-audience` field value: the DID of the host the request
  /// is addressed to, or `nil` for the exchange, which sends no such field.
  public let audience: String?

  /// The `signature-input` field value, labelled `atproto-space`.
  public let signatureInput: String

  /// The `signature` field value: the 64-byte `r` and `s` of the ECDSA
  /// signature, not DER, as a byte sequence labelled `atproto-space`.
  public let signature: String

  /// The fields to attach to the request, in the order they are signed.
  public var headerFields: [(name: String, value: String)] {
    var fields = [(name: "authorization", value: authorization)]
    if let audience {
      fields.append((name: "atproto-space-audience", value: audience))
    }
    fields.append((name: "signature-input", value: signatureInput))
    fields.append((name: "signature", value: signature))
    return fields
  }

  /// Signs the exchange that trades `delegationToken` for a space credential.
  ///
  /// Covers `authorization` alone and names `key` in `keyid` as its
  /// `did:key`, which is the key the issued credential is bound to.
  ///
  /// - Throws: ``SpaceRequestSignatureError/unsupportedKeyType`` when `key` is
  ///   not P-256, ``SpaceRequestSignatureError/invalidFieldValue`` when
  ///   `delegationToken` is empty or contains a line break.
  public static func exchange(delegationToken: String, key: PrivateKey) throws -> Self {
    guard key.type == .p256 else { throw SpaceRequestSignatureError.unsupportedKeyType }
    let parameters = "(\"authorization\");keyid=\"\(key.publicKey.did)\""
    return try Self(
      authorization: "Bearer \(fieldValue(delegationToken))", audience: nil,
      parameters: parameters, key: key)
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
      authorization: "Atproto-Space \(fieldValue(credential))",
      audience: fieldValue(audience),
      parameters: "(\"authorization\" \"atproto-space-audience\")", key: key)
  }

  private init(authorization: String, audience: String?, parameters: String, key: PrivateKey) throws {
    // The signature base of RFC 9421 §2.5: one line per covered component, then
    // the parameters, joined by single line feeds with no trailing one.
    var lines = ["\"authorization\": \(authorization)"]
    if let audience {
      lines.append("\"atproto-space-audience\": \(audience)")
    }
    lines.append("\"@signature-params\": \(parameters)")
    let signature = try key.sign(Data(lines.joined(separator: "\n").utf8))

    self.authorization = authorization
    self.audience = audience
    signatureInput = "atproto-space=\(parameters)"
    self.signature = "atproto-space=:\(signature.base64EncodedString()):"
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
  /// ``authorization``, which carries the token or the credential.
  public var description: String {
    "SpaceRequestSignature(audience: \(audience ?? "nil"))"
  }
}
