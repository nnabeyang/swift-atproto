public struct DIDDocument: Codable, Sendable {
    public let context: [String]
    public let did: String
    public let alsoKnownAs: [String]?
    public let verificationMethod: [DocVerificationMethod]?
    public let service: [DocService]?

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case did = "id"
        case alsoKnownAs
        case verificationMethod
        case service
    }
}

public struct DocVerificationMethod: Codable, Sendable {
    let id: String
    let type: String
    let controller: String
    let publicKeyMultibase: String
}

public struct DocService: Codable, Sendable {
    public let id: String
    public let type: String
    public let serviceEndpoint: String
}
