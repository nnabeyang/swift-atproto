import Foundation

public struct LexiconsStore: Codable {
  public let originHash: String?
  public let generator: String
  public let module: String
  public let dependencies: [ResolvedLexiconDependency]

  public init(originHash: String, generator: String, module: String, dependencies: [ResolvedLexiconDependency]) {
    self.originHash = originHash
    self.generator = generator
    self.module = module
    self.dependencies = dependencies
  }

  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(self)
    try data.write(to: url)
  }

  public static func load(from url: URL) throws -> Self {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(Self.self, from: data)
  }
}

public struct ResolvedLexiconDependency: Codable {
  public struct Lexicon: Codable {
    public let prefix: String
    public let path: String
  }

  public struct SourceState: Codable {
    public let tag: String?
    public let revision: String
  }

  public let location: URL
  public let lexicons: [LexiconDependency.Lexicon]
  public let state: SourceState

  public init(config: LexiconDependency, revision: String) {
    location = config.location
    lexicons = config.lexicons
    state = SourceState(tag: config.state.tag, revision: revision)
  }
}
