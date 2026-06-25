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

extension Language {
  // The parsed BCP-47 components: languageCode / script / region, plus the langtag fields the
  // lexicon needs to model verbatim (variants, extensions, privateUse) and the §2.2.8
  // grandfathered match.
  //
  // `Components` is created by the `Language.init(string:)` parser; callers do not construct it
  // directly. Sub-tag fields preserve the wire case verbatim (no normalization).
  public struct Components: Hashable, Sendable {
    // The primary language subtag. nil when the wire string is a grandfathered/irregular tag
    // or a private-use-only tag (`x-…`).
    public let languageCode: LanguageCode?
    public let script: Script?
    public let region: Region?
    public let variants: [Variant]
    public let extensions: [Extension]
    public let privateUse: [String]
    // Per RFC 5646 §2.2.8, grandfathered tags are atomic: only inputs that match a registered
    // tag exactly (case-insensitive) populate this field. Adding any suffix (e.g.,
    // `zh-min-nan-x-foo`) demotes the tag to a normal langtag parse where this is nil.
    public let grandfathered: Grandfathered?
  }

  // A BCP-47 extension: a singleton (ALPHA / DIGIT except `x`) followed by 1+ subtags of
  // length 2-8 alphanumeric, e.g. `u-co-phonebk`. Subtags preserve the wire case verbatim.
  public struct Extension: Hashable, Sendable {
    public let singleton: Character
    public let subtags: [String]
  }

  // RFC 5646 §2.2.8 grandfathered/irregular language tags. The parser matches these
  // case-insensitively but the canonical wire form (as listed below) is the `rawValue`.
  public enum Grandfathered: String, Hashable, Sendable, Codable, CaseIterable {
    // Irregular
    case enGBOed = "en-GB-oed"
    case iAmi = "i-ami"
    case iBnn = "i-bnn"
    case iDefault = "i-default"
    case iEnochian = "i-enochian"
    case iHak = "i-hak"
    case iKlingon = "i-klingon"
    case iLux = "i-lux"
    case iMingo = "i-mingo"
    case iNavajo = "i-navajo"
    case iPwn = "i-pwn"
    case iTao = "i-tao"
    case iTay = "i-tay"
    case iTsu = "i-tsu"
    case sgnBEFR = "sgn-BE-FR"
    case sgnBENL = "sgn-BE-NL"
    case sgnCHDE = "sgn-CH-DE"
    // Regular
    case artLojban = "art-lojban"
    case celGaulish = "cel-gaulish"
    case noBok = "no-bok"
    case noNyn = "no-nyn"
    case zhGuoyu = "zh-guoyu"
    case zhHakka = "zh-hakka"
    case zhMin = "zh-min"
    case zhMinNan = "zh-min-nan"
    case zhXiang = "zh-xiang"
  }
}
