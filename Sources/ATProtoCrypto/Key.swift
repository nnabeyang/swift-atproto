import Crypto
import Multibase
import secp256k1

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

public enum KeyType: String {
  case secp256k1 = "EcdsaSecp256k1VerificationKey2019"
  case p256 = "EcdsaSecp256r1VerificationKey2019"
  case ed25519 = "Ed25519VerificationKey2020"
}

public struct PrivateKey {
  public let type: KeyType
  let raw: Raw

  public init(type: KeyType) throws {
    self.type = type
    switch type {
    case .ed25519:
      raw = .ed25519(Curve25519.Signing.PrivateKey())
    case .p256:
      raw = .p256(P256.Signing.PrivateKey())
    case .secp256k1:
      raw = try .secp256k1(secp256k1.Signing.PrivateKey())
    }
  }

  public init(type: KeyType, rawValue: Data) throws {
    self.type = type
    switch type {
    case .ed25519:
      raw = try .ed25519(Curve25519.Signing.PrivateKey(rawRepresentation: rawValue))
    case .p256:
      raw = try .p256(P256.Signing.PrivateKey(rawRepresentation: rawValue))
    case .secp256k1:
      raw = try .secp256k1(secp256k1.Signing.PrivateKey(dataRepresentation: rawValue))
    }
  }

  public var rawRepresentation: Data {
    switch raw {
    case .ed25519(let raw):
      raw.rawRepresentation
    case .p256(let raw):
      raw.rawRepresentation
    case .secp256k1(let raw):
      raw.dataRepresentation
    }
  }

  public var publicKey: PublicKey {
    switch raw {
    case .ed25519(let raw):
      PublicKey(type: type, raw: .ed25519(raw.publicKey))
    case .p256(let raw):
      PublicKey(type: type, raw: .p256(raw.publicKey))
    case .secp256k1(let raw):
      PublicKey(type: type, raw: .secp256k1(raw.publicKey))
    }
  }

  public func sign(_ data: Data) throws -> Data {
    switch raw {
    case .ed25519(let raw):
      try raw.signature(for: data)
    case .p256(let raw):
      try raw.signature(for: data).rawRepresentation
    case .secp256k1(let raw):
      try raw.signature(for: data).compactRepresentation
    }
  }

  public enum Raw {
    case ed25519(Curve25519.Signing.PrivateKey)
    case p256(P256.Signing.PrivateKey)
    case secp256k1(secp256k1.Signing.PrivateKey)
  }
}

public enum VarintError: Error {
  case overflow
  case notMinimalFound
  case underflow
}

public struct PublicKey {
  let type: KeyType
  let raw: Raw

  public init(type: KeyType, raw: Raw) {
    self.type = type
    self.raw = raw
  }

  var prefix: UInt64 {
    switch type {
    case .ed25519:
      0xED
    case .p256:
      0x1200
    case .secp256k1:
      0xE7
    }
  }

  public var multibaseString: String {
    BaseEncoding.base58btc.encode(data: varEncode(pref: prefix, body: rawBytes))
  }

  public var rawBytes: Data {
    switch raw {
    case .ed25519(let key):
      key.rawRepresentation
    case .p256(let key):
      key.rawRepresentation
    case .secp256k1(let key):
      Data(key.dataRepresentation)
    }
  }

  private func varEncode(pref: UInt64, body: Data) -> Data {
    var buf = varint(UInt64(pref))
    buf.append(contentsOf: body)
    return buf
  }

  private func varint(_ x: UInt64) -> Data {
    var buf: [UInt8] = []
    var x = x
    var i = 0
    repeat {
      buf.append(UInt8(truncatingIfNeeded: x) | 0x80)
      x >>= 7
      i += 1
    } while x >= 0x80
    buf.append(UInt8(x))
    return Data(buf)
  }

  private static func varDecode(buf: Data) throws -> (UInt64, Data) {
    let (prefix, left) = try fromUvarint(buf: buf)
    return (prefix, buf[left...])
  }

  private static let maxLenUvariant63 = 9
  private static let maxValueUvariant63 = (1 << 63) - 1

  private static func fromUvarint(buf: Data) throws -> (UInt64, Int) {
    var x: UInt64 = 0
    var s: UInt = 0
    for (i, b) in buf.enumerated() {
      if (i == 8 && b >= 0x80) || i >= maxLenUvariant63 {
        throw VarintError.overflow
      }
      if b < 0x80 {
        if b == 0, s > 0 {
          throw VarintError.notMinimalFound
        }
        return (x | UInt64(b) << s, i + 1)
      }
      x |= UInt64(b & 0x7F) << s
      s += 7
    }
    throw VarintError.underflow
  }

  private static func keyType(prefix: UInt64) -> KeyType {
    switch prefix {
    case 0xED:
      .ed25519
    case 0x1200:
      .p256
    case 0xE7:
      .secp256k1
    default:
      fatalError("Not supported keyType: \(prefix)")
    }
  }

  public static func publicKeyFromMultibaseString(string: String) throws -> PublicKey {
    let data = try Multibase.BaseEncoding.decode(string).data
    let (prefix, raw) = try varDecode(buf: data)
    let keyType = keyType(prefix: prefix)
    return try keyDataAndTypeToKey(keyType: keyType, raw: raw)
  }

  static func keyDataAndTypeToKey(keyType: KeyType, raw: Data) throws -> PublicKey {
    switch keyType {
    case .ed25519:
      let raw = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
      return PublicKey(type: keyType, raw: .ed25519(raw))
    case .p256:
      let raw = try P256.Signing.PublicKey(rawRepresentation: raw)
      return PublicKey(type: keyType, raw: .p256(raw))
    case .secp256k1:
      let format: secp256k1.Format = raw.count == secp256k1.Format.compressed.length ? .compressed : .uncompressed
      let pubKey = try secp256k1.Signing.PublicKey(dataRepresentation: raw, format: format)
      return try PublicKey(type: keyType, raw: .secp256k1(pubKey.compressed))
    }
  }

  public func isValidSignature(signature: any DataProtocol, for message: any DataProtocol) -> Bool {
    switch raw {
    case .ed25519(let raw):
      return raw.isValidSignature(signature, for: message)
    case .secp256k1(let raw):
      guard let signature = try? secp256k1.Signing.ECDSASignature(compactRepresentation: signature).normalize else { return false }
      let hash = SHA256.hash(data: message)
      return raw.isValidSignature(signature, for: hash)
    case .p256(let raw):
      guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
      return raw.isValidSignature(signature, for: message)
    }
  }

  public var did: String {
    "did:key:\(multibaseString)"
  }

  public enum Raw {
    case ed25519(Curve25519.Signing.PublicKey)
    case p256(P256.Signing.PublicKey)
    case secp256k1(secp256k1.Signing.PublicKey)
  }
}

extension secp256k1.Signing.PublicKey {
  var compressed: Self {
    get throws {
      guard format != .compressed else {
        return self
      }
      let format = secp256k1.Format.compressed
      let context = secp256k1.Context.rawRepresentation
      var pubKeyLen = format.length
      var combinedKey = secp256k1_pubkey()
      var combinedBytes = [UInt8](repeating: 0, count: pubKeyLen)

      let item = Swift.withUnsafeBytes(of: rawRepresentation) { buf in
        buf.baseAddress!.assumingMemoryBound(to: secp256k1_pubkey.self)
      }
      guard secp256k1_ec_pubkey_combine(context, &combinedKey, [item], 1) > 0,
        secp256k1_ec_pubkey_serialize(context, &combinedBytes, &pubKeyLen, &combinedKey, format.rawValue) > 0
      else {
        throw secp256k1Error.underlyingCryptoError
      }
      return try Self(dataRepresentation: combinedBytes, format: format)
    }
  }
}

extension secp256k1.Signing.ECDSASignature {
  fileprivate var normalize: secp256k1.Signing.ECDSASignature {
    get throws {
      let context = secp256k1.Context.rawRepresentation
      var signature = secp256k1_ecdsa_signature()
      var resultSignature = secp256k1_ecdsa_signature()

      dataRepresentation.copyToUnsafeMutableBytes(of: &signature.data)

      guard
        secp256k1_ecdsa_signature_normalize(
          context,
          &resultSignature,
          &signature
        ) != 0
      else {
        return self
      }

      return try secp256k1.Signing.ECDSASignature(dataRepresentation: resultSignature.dataValue)
    }
  }
}
