import Foundation

public struct LexiconConfig: Codable, Sendable {
    public let dependencies: [LexiconDependency]
    public let module: String?
}

public struct LexiconDependency: Codable, Sendable {
    public struct Lexicon: Codable, Sendable {
        public let prefix: String
        public let path: String
    }

    public struct SourceState: Codable, Sendable {
        public let tag: String
    }

    public let location: URL
    public let lexicons: [Lexicon]
    public let state: SourceState
}
