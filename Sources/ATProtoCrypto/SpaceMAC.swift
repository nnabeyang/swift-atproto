import Crypto
import Multibase

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Why a space MAC could not be established, read, or computed.
///
/// No case carries a secret, so an error is safe to log. A repo host reports
/// every one of these to a syncer as `BadSpaceMac`.
public enum SpaceMACError: Error, Hashable, Sendable {
  /// A KEM key or key share is not a P-256 `did:key` or multikey.
  case invalidKey
  /// The header is absent.
  case missingHeader
  /// The header is not a Structured Field Dictionary, or a member has the
  /// wrong kind of value.
  case malformedHeader
  /// The header names another MAC type than the method uses.
  case unsupportedType
  /// The header names another version than the MAC type is on.
  case unsupportedVersion
  /// A string bound into a MAC is longer than its uint16 length prefix allows.
  case fieldTooLong
}

/// What a space MAC authenticates, as named in the `type` of its headers.
public enum SpaceMACType: String, Hashable, Sendable, CaseIterable {
  /// A repo commit: `getLatestCommit`, `getRepo`, and `listRepoOps`.
  case repo = "atproto-space-repo"
  /// A record's URI and CID: `getRecord`.
  case record = "atproto-space-record"

  /// The version the type is on, sent as `ver`. A commit MAC shares its
  /// version with the commit format.
  public var version: Int { 1 }
}

/// The shared secret a syncer establishes with a repo host for one request.
///
/// The syncer encapsulates against the author's `#atproto_kem` key, sends
/// ``keyShare`` with its MAC request, and keeps ``sharedSecret`` to verify the
/// MAC the response carries. The secret is an HPKE secret export
/// ([RFC 9180 §6.2](https://www.rfc-editor.org/rfc/rfc9180#section-6.2)) in
/// base mode, with DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, the Export-only
/// AEAD, the `info` `atproto-mac`, and an empty exporter context, so nothing
/// is encrypted.
///
/// Use a new encapsulation for every request, including retries and each page
/// of a paginated response. It is unrelated to the key a space credential is
/// bound to.
public struct SpaceKeyEncapsulation: Sendable {
  /// HPKE's `enc`, the syncer's ephemeral P-256 public key, as a `did:key`.
  /// HPKE encodes `enc` as an uncompressed point, but a `did:key` carries the
  /// compressed one.
  public let keyShare: String

  /// The 32-byte secret that keys the response MAC.
  public let sharedSecret: SymmetricKey

  /// Encapsulates against `authorKEMKey`, a P-256 `did:key` or the
  /// `publicKeyMultibase` of an `#atproto_kem` verification method.
  ///
  /// - Throws: ``SpaceMACError/invalidKey`` when the key is not P-256.
  public static func encapsulate(authorKEMKey: String) throws -> Self {
    let author = try Self.agreementKey(authorKEMKey)
    do {
      let sender = try HPKE.Sender(recipientKey: author, ciphersuite: ciphersuite, info: info)
      let enc = try P256.Signing.PublicKey(x963Representation: sender.encapsulatedKey)
      return Self(
        keyShare: PublicKey(type: .p256, raw: .p256(enc)).did,
        sharedSecret: try sender.exportSecret(context: Data(), outputByteCount: 32))
    } catch {
      throw SpaceMACError.invalidKey
    }
  }

  /// The repo host's side: derives the secret for `keyShare` with the
  /// author's KEM private key.
  ///
  /// - Throws: ``SpaceMACError/invalidKey`` when `keyShare` or `authorKEMKey`
  ///   is not P-256.
  public static func decapsulate(keyShare: String, authorKEMKey: PrivateKey) throws -> SymmetricKey {
    guard authorKEMKey.type == .p256 else { throw SpaceMACError.invalidKey }
    return try export(
      enc: try agreementKey(keyShare).x963Representation,
      authorKEMKey: authorKEMKey, info: info, context: Data())
  }

  /// The secret HPKE exports for `enc` under `info` and `context`, as the
  /// repo host derives it. Separate from ``decapsulate(keyShare:authorKEMKey:)``
  /// so that the published test vectors, which use another `info`, can be
  /// checked.
  static func export(enc: Data, authorKEMKey: PrivateKey, info: Data, context: Data) throws -> SymmetricKey {
    do {
      let author = try P256.KeyAgreement.PrivateKey(
        rawRepresentation: authorKEMKey.rawRepresentation)
      let recipient = try HPKE.Recipient(
        privateKey: author, ciphersuite: ciphersuite, info: info, encapsulatedKey: enc)
      return try recipient.exportSecret(context: context, outputByteCount: 32)
    } catch {
      throw SpaceMACError.invalidKey
    }
  }

  /// KEM `0x0010`, KDF `0x0001`, and AEAD `0xFFFF`.
  private static let ciphersuite = HPKE.Ciphersuite(
    kem: .P256_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .exportOnly)

  /// A fixed label that ties the secret to this protocol.
  private static let info = Data("atproto-mac".utf8)

  // The multicodec prefix of a P-256 public key, 0x1200 as an unsigned varint.
  private static let p256Multicodec: [UInt8] = [0x80, 0x24]

  static func agreementKey(_ key: String) throws -> P256.KeyAgreement.PublicKey {
    let multibase = key.hasPrefix("did:key:") ? String(key.dropFirst("did:key:".count)) : key
    guard multibase.hasPrefix("z"),
      let decoded = try? BaseEncoding.decode(multibase), decoded.base == .base58btc,
      decoded.data.starts(with: p256Multicodec)
    else { throw SpaceMACError.invalidKey }
    let point = decoded.data.dropFirst(p256Multicodec.count)
    do {
      // Keys written before compressed multikeys carry the 64-byte coordinates.
      return point.count == 64
        ? try P256.KeyAgreement.PublicKey(rawRepresentation: point)
        : try P256.KeyAgreement.PublicKey(compressedRepresentation: point)
    } catch {
      throw SpaceMACError.invalidKey
    }
  }
}

/// The MACs that authenticate space commits and records to a syncer, and the
/// headers that carry them.
///
/// A space repo commit carries no signature. The syncer and the repo host
/// share a secret for each request (``SpaceKeyEncapsulation``), and the host
/// returns an HMAC-SHA256 in `Atproto-Space-Mac`. A leaked response therefore
/// proves nothing about authorship to a third party.
public enum SpaceMAC {
  /// The request header that asks for a MAC and carries the key share.
  public static let wantMACHeaderName = "atproto-space-want-mac"

  /// The response header that carries the MAC.
  public static let macHeaderName = "atproto-space-mac"

  /// The `Atproto-Space-Want-Mac` value for `type`, for example
  /// `type="atproto-space-repo", ver=1, key_share="did:key:zDna…"`.
  public static func wantMACHeader(type: SpaceMACType, keyShare: String) -> String {
    "type=\"\(type.rawValue)\", ver=\(type.version), key_share=\"\(keyShare)\""
  }

  /// The `Atproto-Space-Mac` value for `type` and `mac`, with the MAC as a
  /// padded base64 byte sequence.
  public static func macHeader(type: SpaceMACType, mac: Data) -> String {
    "type=\"\(type.rawValue)\", ver=\(type.version), mac=:\(mac.base64EncodedString()):"
  }

  /// The `key_share` of an `Atproto-Space-Want-Mac` value, after checking its
  /// `type` and `ver`.
  public static func keyShare(fromWantMACHeader value: String?, type: SpaceMACType) throws -> String {
    guard case .string(let keyShare) = try members(of: value, type: type)["key_share"] else {
      throw SpaceMACError.malformedHeader
    }
    return keyShare
  }

  /// The MAC of an `Atproto-Space-Mac` value, after checking its `type` and
  /// `ver`.
  public static func mac(fromMACHeader value: String?, type: SpaceMACType) throws -> Data {
    guard case .bytes(let mac) = try members(of: value, type: type)["mac"] else {
      throw SpaceMACError.malformedHeader
    }
    return mac
  }

  /// The commit MAC:
  ///
  /// ```
  /// context = "atproto-space-repo-v1"
  ///    || uint16be(len(space)) || space
  ///    || uint16be(len(repo))  || repo
  ///    || uint16be(len(rev))   || rev
  /// mac = HMAC-SHA256(shared_secret, context || data)
  /// ```
  public static func commitMAC(
    sharedSecret: SymmetricKey, space: String, repo: String, rev: String, data: Data
  ) throws -> Data {
    Data(
      HMAC<SHA256>.authenticationCode(
        for: try commitMessage(space: space, repo: repo, rev: rev, data: data),
        using: sharedSecret))
  }

  /// Whether `mac` authenticates the commit, compared in constant time.
  public static func isValidCommitMAC(
    _ mac: Data, sharedSecret: SymmetricKey, space: String, repo: String, rev: String, data: Data
  ) -> Bool {
    guard let message = try? commitMessage(space: space, repo: repo, rev: rev, data: data) else {
      return false
    }
    return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: sharedSecret)
  }

  /// The record MAC over the full space record URI and the binary CID:
  ///
  /// ```
  /// context = "atproto-space-record-v1" || uint16be(len(uri)) || uri
  /// mac = HMAC-SHA256(shared_secret, context || record_cid_bytes)
  /// ```
  public static func recordMAC(sharedSecret: SymmetricKey, uri: String, cid: Data) throws -> Data {
    Data(
      HMAC<SHA256>.authenticationCode(
        for: try recordMessage(uri: uri, cid: cid), using: sharedSecret))
  }

  /// Whether `mac` authenticates the record's URI and CID, compared in
  /// constant time.
  public static func isValidRecordMAC(
    _ mac: Data, sharedSecret: SymmetricKey, uri: String, cid: Data
  ) -> Bool {
    guard let message = try? recordMessage(uri: uri, cid: cid) else { return false }
    return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: sharedSecret)
  }

  private static func commitMessage(space: String, repo: String, rev: String, data: Data) throws -> Data {
    var message = Data("\(SpaceMACType.repo.rawValue)-v\(SpaceMACType.repo.version)".utf8)
    for field in [space, repo, rev] {
      message += try lengthPrefixed(field)
    }
    return message + data
  }

  private static func recordMessage(uri: String, cid: Data) throws -> Data {
    Data("\(SpaceMACType.record.rawValue)-v\(SpaceMACType.record.version)".utf8)
      + (try lengthPrefixed(uri)) + cid
  }

  private static func lengthPrefixed(_ value: String) throws -> Data {
    let bytes = Data(value.utf8)
    guard bytes.count <= Int(UInt16.max) else { throw SpaceMACError.fieldTooLong }
    return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 0xff)]) + bytes
  }

  private static func members(of value: String?, type: SpaceMACType) throws -> [String: StructuredItem] {
    guard let value else { throw SpaceMACError.missingHeader }
    guard let members = StructuredDictionary.parse(value) else {
      throw SpaceMACError.malformedHeader
    }
    guard case .string(type.rawValue) = members["type"] else {
      throw SpaceMACError.unsupportedType
    }
    guard case .integer(Int64(type.version)) = members["ver"] else {
      throw SpaceMACError.unsupportedVersion
    }
    return members
  }
}

/// A bare item of an RFC 9651 Structured Field.
enum StructuredItem: Hashable, Sendable {
  case integer(Int64)
  case decimal(String)
  case string(String)
  case token(String)
  case bytes(Data)
  case boolean(Bool)
  /// An inner list. Its items are not kept, because no header read here uses
  /// one; a caller expecting a bare item treats it as malformed.
  case innerList
}

/// A parser for RFC 9651 §4.2.2 Dictionaries, keeping each member's bare item
/// and discarding parameters. A later duplicate key overrides an earlier one,
/// as the RFC requires.
enum StructuredDictionary {
  static func parse(_ input: String) -> [String: StructuredItem]? {
    var parser = Parser(Array(input.utf8))
    return parser.dictionary()
  }

  private struct Parser {
    var bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func skip(_ predicate: (UInt8) -> Bool) {
      while let byte = current, predicate(byte) { index += 1 }
    }

    mutating func dictionary() -> [String: StructuredItem]? {
      skip { $0 == 0x20 }
      var members: [String: StructuredItem] = [:]
      while current != nil {
        guard let key = key() else { return nil }
        let item: StructuredItem
        if current == UInt8(ascii: "=") {
          index += 1
          if current == UInt8(ascii: "(") {
            guard innerList() else { return nil }
            item = .innerList
          } else {
            guard let bare = bareItem() else { return nil }
            item = bare
          }
        } else {
          item = .boolean(true)
        }
        guard parameters() else { return nil }
        members[key] = item
        skip { $0 == 0x20 || $0 == 0x09 }
        guard let byte = current else { return members }
        guard byte == UInt8(ascii: ",") else { return nil }
        index += 1
        skip { $0 == 0x20 || $0 == 0x09 }
        // A trailing comma is not allowed.
        guard current != nil else { return nil }
      }
      return members
    }

    mutating func key() -> String? {
      guard let first = current, Self.isLowerAlpha(first) || first == UInt8(ascii: "*") else {
        return nil
      }
      let start = index
      skip {
        Self.isLowerAlpha($0) || Self.isDigit($0) || $0 == UInt8(ascii: "_")
          || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "*")
      }
      return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func parameters() -> Bool {
      while current == UInt8(ascii: ";") {
        index += 1
        skip { $0 == 0x20 }
        guard key() != nil else { return false }
        if current == UInt8(ascii: "=") {
          index += 1
          guard bareItem() != nil else { return false }
        }
      }
      return true
    }

    mutating func innerList() -> Bool {
      index += 1
      while true {
        skip { $0 == 0x20 }
        guard let byte = current else { return false }
        if byte == UInt8(ascii: ")") {
          index += 1
          return parameters()
        }
        guard bareItem() != nil, parameters() else { return false }
        guard current == 0x20 || current == UInt8(ascii: ")") else { return false }
      }
    }

    mutating func bareItem() -> StructuredItem? {
      guard let byte = current else { return nil }
      switch byte {
      case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return number()
      case UInt8(ascii: "\""): return string()
      case UInt8(ascii: ":"): return byteSequence()
      case UInt8(ascii: "?"): return boolean()
      case UInt8(ascii: "*"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"):
        return token()
      default: return nil
      }
    }

    mutating func number() -> StructuredItem? {
      let start = index
      if current == UInt8(ascii: "-") { index += 1 }
      let digitsStart = index
      skip(Self.isDigit)
      let integerDigits = index - digitsStart
      guard integerDigits > 0 else { return nil }
      if current == UInt8(ascii: ".") {
        guard integerDigits <= 12 else { return nil }
        index += 1
        let fractionStart = index
        skip(Self.isDigit)
        let fractionDigits = index - fractionStart
        guard (1...3).contains(fractionDigits) else { return nil }
        return .decimal(String(decoding: bytes[start..<index], as: UTF8.self))
      }
      guard integerDigits <= 15,
        let value = Int64(String(decoding: bytes[start..<index], as: UTF8.self))
      else { return nil }
      return .integer(value)
    }

    mutating func string() -> StructuredItem? {
      index += 1
      var output: [UInt8] = []
      while let byte = current {
        index += 1
        switch byte {
        case UInt8(ascii: "\\"):
          guard let escaped = current, escaped == UInt8(ascii: "\\") || escaped == UInt8(ascii: "\"")
          else { return nil }
          index += 1
          output.append(escaped)
        case UInt8(ascii: "\""):
          return .string(String(decoding: output, as: UTF8.self))
        case 0x20...0x7e:
          output.append(byte)
        default:
          return nil
        }
      }
      return nil
    }

    mutating func byteSequence() -> StructuredItem? {
      index += 1
      let start = index
      skip {
        Self.isLowerAlpha($0) || ($0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z"))
          || Self.isDigit($0) || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "/")
          || $0 == UInt8(ascii: "=")
      }
      guard current == UInt8(ascii: ":") else { return nil }
      var encoded = String(decoding: bytes[start..<index], as: UTF8.self)
      index += 1
      // Parsers tolerate missing padding, as the reference implementation does.
      encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
      guard let data = Data(base64Encoded: encoded) else { return nil }
      return .bytes(data)
    }

    mutating func boolean() -> StructuredItem? {
      index += 1
      guard let byte = current else { return nil }
      index += 1
      switch byte {
      case UInt8(ascii: "1"): return .boolean(true)
      case UInt8(ascii: "0"): return .boolean(false)
      default: return nil
      }
    }

    mutating func token() -> StructuredItem? {
      let start = index
      index += 1
      skip {
        (0x21...0x7e).contains($0)
          && !"\"(),;<=>?@[\\]{}".utf8.contains($0)
      }
      return .token(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    static func isLowerAlpha(_ byte: UInt8) -> Bool {
      byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
    }

    static func isDigit(_ byte: UInt8) -> Bool {
      byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
  }
}
