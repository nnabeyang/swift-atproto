import Multibase

#if !canImport(Darwin)
  import FoundationEssentials
#else
  import Foundation
#endif

public enum DIDError: Error {
  case notFound
}

public struct DID: Codable {
  public let raw: String
  public let proto: String
  public let value: String
  public let fragment: String

  private enum CodingKeys: String, CodingKey {
    case raw
    case proto
    case value
    case fragment
  }

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

public struct Document: Codable {
  public let context: [String]
  public let id: DID
  public let alsoKnownAs: [String]?
  public let verificationMethod: [VerificationMethod]
  public let service: [Service]

  private enum CodingKeys: String, CodingKey {
    case context = "@context"
    case id
    case alsoKnownAs
    case verificationMethod
    case service
  }

  public func getPublicKey(id: String) throws -> PublicKey {
    for vm in verificationMethod {
      if id.isEmpty || id == vm.id || (id.hasPrefix("#") && "\(self.id.raw)\(id)" == vm.id) {
        return try vm.publicKey
      }
    }
    throw DIDError.notFound
  }
}

public struct Service: Codable {
  public let id: DID
  public let type: String
  public let serviceEndpoint: String
}

public struct VerificationMethod: Codable {
  public let id: String
  public let type: VerificationKeyType
  public let controller: String
  // Not Supported publicKeyJwk key
  // public let publicKeyJwk: PublicKeyJWK?
  public let publicKeyMultibase: String?

  public enum VerificationKeyType: String, Codable {
    case multiKey = "Multikey"
    case secp256k1 = "EcdsaSecp256k1VerificationKey2019"
    case p256 = "EcdsaSecp256r1VerificationKey2019"
    case ed25519 = "Ed25519VerificationKey2020"
  }

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
