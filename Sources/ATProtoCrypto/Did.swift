import Multibase

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A lookup that found no matching entry in a DID document.
public enum DIDError: Error {
  /// No verification method matched the requested id.
  case notFound
}

/// A parsed Decentralized Identifier.
///
/// The wire string is kept verbatim in ``raw`` and the three parsed components
/// are exposed separately. A value that is only a fragment — `"#atproto"` —
/// parses with an empty ``proto`` and ``value``, which is how a DID document's
/// relative references are represented.
public struct DID: Codable {
  /// The identifier exactly as it was written.
  public let raw: String
  /// The DID method, such as `plc` or `web`.
  public let proto: String
  /// The method-specific identifier following the method.
  public let value: String
  /// The `#`-prefixed fragment, or an empty string when there is none.
  public let fragment: String

  private enum CodingKeys: String, CodingKey {
    case raw
    case proto
    case value
    case fragment
  }

  /// Parses a DID.
  ///
  /// - Throws: `DecodingError.dataCorrupted` when `raw` is neither a bare
  ///   fragment nor three colon-separated parts beginning with `did`.
  public init(raw: String) throws(DecodingError) {
    self.raw = raw
    guard !raw.hasPrefix("#") else {
      self.proto = ""
      self.value = ""
      self.fragment = raw
      return
    }
    let dfrag = raw.split(separator: "#", maxSplits: 2)
    let segm = raw.split(separator: ":", maxSplits: 3)
    guard segm.count == 3 else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid did: must contain three parts: \(segm)"))
    }
    guard segm[0] == "did" else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid did: first segment must be 'did'"))
    }

    self.proto = String(segm[1])
    self.value = String(segm[2])
    self.fragment = dfrag.count == 2 ? "#\(dfrag[1])" : ""
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    self = try DID(raw: raw)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(raw)
  }
}

/// A DID document: the keys and service endpoints an identity publishes.
public struct Document: Codable {
  public let context: [String]
  /// The DID this document describes.
  public let id: DID
  /// The handles and other identifiers this DID claims.
  public let alsoKnownAs: [String]?
  /// The public keys this identity publishes.
  public let verificationMethod: [VerificationMethod]
  /// The services this identity publishes, such as its PDS.
  public let service: [Service]

  private enum CodingKeys: String, CodingKey {
    case context = "@context"
    case id
    case alsoKnownAs
    case verificationMethod
    case service
  }

  /// Decodes the public key of a verification method.
  ///
  /// `id` may be a full method id, a `#fragment` resolved against this
  /// document's own DID, or an empty string to take the first method.
  ///
  /// - Throws: ``DIDError/notFound`` when no method matches.
  public func getPublicKey(id: String) throws -> PublicKey {
    for vm in verificationMethod {
      if id.isEmpty || id == vm.id || (id.hasPrefix("#") && "\(self.id.raw)\(id)" == vm.id) {
        return try vm.publicKey
      }
    }
    throw DIDError.notFound
  }
}

/// A service endpoint published by a ``Document``.
public struct Service: Codable {
  /// The service identifier, usually a fragment such as
  /// `#atproto_pds`.
  public let id: DID
  /// The service type, such as `AtprotoPersonalDataServer`.
  public let type: String
  /// The endpoint URL.
  public let serviceEndpoint: String
}

/// A public key published by a ``Document``.
public struct VerificationMethod: Codable {
  /// The method identifier, usually the DID followed by a fragment such as
  /// `#atproto`.
  public let id: String
  /// The key type, which selects the curve unless it is
  /// ``VerificationKeyType/multiKey``.
  public let type: VerificationKeyType
  /// The DID that controls this key.
  public let controller: String
  // Not Supported publicKeyJwk key
  // public let publicKeyJwk: PublicKeyJWK?
  public let publicKeyMultibase: String?

  /// The `type` a DID document gives a verification method.
  ///
  /// ``multiKey`` carries the curve in the encoded key itself; the other cases
  /// name it directly and map onto ``KeyType``.
  public enum VerificationKeyType: String, Codable {
    case multiKey = "Multikey"
    case secp256k1 = "EcdsaSecp256k1VerificationKey2019"
    case p256 = "EcdsaSecp256r1VerificationKey2019"
    case ed25519 = "Ed25519VerificationKey2020"
  }

  /// Decodes this method's key.
  ///
  /// - Throws: `CocoaError.featureUnsupported` when the method publishes no
  ///   `publicKeyMultibase` — a JWK-only method, for instance — or names a type
  ///   this module cannot decode.
  public var publicKey: PublicKey {
    get throws {
      guard let publicKeyMultibase else {
        throw CocoaError(.featureUnsupported)
      }
      switch type {
      case .multiKey:
        return try PublicKey.publicKeyFromMultibaseString(string: publicKeyMultibase)
      default:
        guard let keyType = KeyType(rawValue: type.rawValue) else {
          throw CocoaError(.featureUnsupported)
        }
        let data = try BaseEncoding.decode(publicKeyMultibase).data
        return try PublicKey.keyDataAndTypeToKey(keyType: keyType, raw: data)
      }
    }
  }
}
