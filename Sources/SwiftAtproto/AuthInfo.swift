import Foundation

public protocol AuthInfo: Sendable, Equatable, Hashable {
    var accessJwt: String { get set }
    var refreshJwt: String { get set }
    var handle: String { get set }
    var did: String { get set }
    var serviceEndPoint: URL? { get set }
}

public extension AuthInfo {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accessJwt == rhs.accessJwt && lhs.refreshJwt == rhs.refreshJwt
    }
}
