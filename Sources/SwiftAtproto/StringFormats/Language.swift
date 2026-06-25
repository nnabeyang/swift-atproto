import Foundation

// Type for the lexicon `language` string format: a range-based BCP-47 (RFC 5646) parser whose
// `rawValue` keeps the wire string verbatim and acts as the single source of truth — parsed
// `Components` are never re-serialized back to an identifier.
//
// Scope: the canonical BCP-47 langtag grammar plus the RFC 5646 §2.2.8 grandfathered/irregular
// whitelist, in strict mode. The parser only validates grammar — it does not consult any subtag
// registry. A lenient mode (`_` separators, etc.) and canonicalization are intentionally NOT
// supported.
public struct Language: Hashable, Sendable {}

extension Language {
  // BCP-47 primary language subtag: 2-3 ALPHA, or 4 ALPHA (reserved), or 5-8 ALPHA (registered).
  public struct LanguageCode: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try String(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try rawValue.encode(to: encoder) }
  }

  // BCP-47 script subtag: 4 ALPHA, e.g. `Latn`, `Hant`.
  public struct Script: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try String(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try rawValue.encode(to: encoder) }
  }

  // BCP-47 region subtag: 2 ALPHA (e.g. `US`) or 3 DIGIT (e.g. `419`).
  public struct Region: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try String(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try rawValue.encode(to: encoder) }
  }

  // BCP-47 variant subtag: 5-8 alphanum, or DIGIT + 3 alphanum (e.g. `1901`, `rozaj`).
  public struct Variant: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try String(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try rawValue.encode(to: encoder) }
  }
}
