public struct DIDDocument: Codable, Sendable, Hashable {
  public let context: [String]
  public let did: FormatString<DID>
  public let alsoKnownAs: [String]?
  public let verificationMethod: [DocVerificationMethod]?
  public let service: [DocService]?

  public init(
    context: [String],
    did: FormatString<DID>,
    alsoKnownAs: [String]? = nil,
    verificationMethod: [DocVerificationMethod]? = nil,
    service: [DocService]? = nil
  ) {
    self.context = context
    self.did = did
    self.alsoKnownAs = alsoKnownAs
    self.verificationMethod = verificationMethod
    self.service = service
  }

  enum CodingKeys: String, CodingKey {
    case context = "@context"
    case did = "id"
    case alsoKnownAs
    case verificationMethod
    case service
  }
}

public struct DocVerificationMethod: Codable, Sendable, Hashable {
  public let id: String
  public let type: String
  public let controller: String
  public let publicKeyMultibase: String

  public init(id: String, type: String, controller: String, publicKeyMultibase: String) {
    self.id = id
    self.type = type
    self.controller = controller
    self.publicKeyMultibase = publicKeyMultibase
  }
}

public struct DocService: Codable, Sendable, Hashable {
  public let id: String
  public let type: String
  public let serviceEndpoint: String

  public init(id: String, type: String, serviceEndpoint: String) {
    self.id = id
    self.type = type
    self.serviceEndpoint = serviceEndpoint
  }
}
