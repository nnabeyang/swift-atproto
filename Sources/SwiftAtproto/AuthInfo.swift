public struct AuthInfo: Codable {
    public var accessJwt: String = ""
    public var refreshJwt: String = ""
    public var handle: String = ""
    public var did: String = ""
    public init() {}
}
