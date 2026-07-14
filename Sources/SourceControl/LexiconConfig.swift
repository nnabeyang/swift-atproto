import Foundation

public struct GenerateOption: OptionSet, Codable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    var options: GenerateOption = []
    let names: [String]
    do {
      names = try [String](from: decoder)
    } catch DecodingError.typeMismatch {
      names = try [String(from: decoder)]
    }
    for name in names {
      switch name {
      case "client":
        options.insert(.client)
      case "server":
        options.insert(.server)
      default:
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown generate option: \(name)"))
      }
    }
    self = options
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .client:
      try "client".encode(to: encoder)
    case .server:
      try "server".encode(to: encoder)
    default:
      throw EncodingError.invalidValue("\(self)", EncodingError.Context(codingPath: [], debugDescription: "Unhandled generate option"))
    }
  }

  public static let client = Self(rawValue: 1 << 0)
  public static let server = Self(rawValue: 1 << 1)
}

public struct LexiconConfig: Encodable, DecodableWithConfiguration, Sendable {
  public let dependencies: [LexiconDependency]
  public let module: String
  public let generate: GenerateOption

  enum CodingKeys: String, CodingKey {
    case dependencies
    case module
    case generate
  }

  public init(from decoder: Decoder, configuration outdir: String?) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    dependencies = try container.decode([LexiconDependency].self, forKey: .dependencies)
    module = try outdir ?? container.decodeIfPresent(String.self, forKey: .module) ?? Self.defaultModule
    generate = try container.decodeIfPresent(GenerateOption.self, forKey: .generate) ?? .client
  }

  private static let defaultModule = "."
}

public struct LexiconDependency: Codable, Sendable {
  public struct Lexicon: Codable, Sendable {
    /// Source-repo-relative directory that holds the lexicon JSON files. The
    /// install step reads each JSON's `id`, joins it as `<id-as-path>.json`
    /// onto `.lexicons/lexicons/`, and copies (or symlinks, for local deps)
    /// the file there. No transformation of `path` beyond this is performed.
    public let path: String
    /// Optional allowlist. When present, only the listed NSIDs are installed
    /// (each expected to live at `<path>/<nsid-as-path>.json` in the source).
    /// When absent, every `.json` file under `<path>` is discovered
    /// recursively and installed based on its own `id`.
    public let nsIds: [NSID]?

    public init(path: String, nsIds: [NSID]? = nil) {
      self.path = path
      self.nsIds = nsIds
    }
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
