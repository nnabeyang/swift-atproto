import Foundation

public struct AuthInfo: Codable, Sendable {
    public var accessJwt: String
    public var refreshJwt: String
    public var handle: String
    public var did: String
    public var serviceEndPoint: URL?

    public init(accessJwt: String = "", refreshJwt: String = "", handle: String = "", did: String = "", serviceEndPoint: URL? = nil) {
        self.accessJwt = accessJwt
        self.refreshJwt = refreshJwt
        self.handle = handle
        self.did = did
        self.serviceEndPoint = serviceEndPoint
    }
}
