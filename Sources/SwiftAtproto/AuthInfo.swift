import Foundation

public struct AuthInfo: Codable {
    public var accessJwt: String = ""
    public var refreshJwt: String = ""
    public var handle: String = ""
    public var did: String = ""
    public var serviceEndPoint: URL?
    public init() {}
}
