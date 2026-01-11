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

  public enum SourceState: Codable, Sendable {
    case tag(String)
    case revision(String)

    enum CodingKeys: String, CodingKey {
      case tag
      case revision
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      guard container.allKeys.count == 1 else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Exactly one of 'tag' or 'revision' must be specified"))
      }
      switch container.allKeys[0] {
      case .tag:
        self = try .tag(container.decode(String.self, forKey: .tag))
      case .revision:
        self = try .revision(container.decode(String.self, forKey: .revision))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .tag(let value):
        try container.encode(value, forKey: .tag)
      case .revision(let value):
        try container.encode(value, forKey: .revision)
      }
    }

    public var tag: String? {
      switch self {
      case .tag(let tag):
        tag
      case .revision:
        nil
      }
    }
  }

  public let location: URL
  public let lexicons: [Lexicon]
  public let state: SourceState
}
