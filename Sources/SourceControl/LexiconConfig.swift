import Foundation

public struct LexiconConfig: Codable {
    public let dependencies: [LexiconDependency]
}

public struct LexiconDependency: Codable {
    public struct Lexicon: Codable {
        public let prefix: String
        public let path: String
    }

    public struct SourceState: Codable {
        public let tag: String
    }

    public let location: URL
    public let lexicons: [Lexicon]
    public let state: SourceState
}
