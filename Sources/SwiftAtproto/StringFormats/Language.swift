import Foundation

// Type for the lexicon `language` string format: a range-based BCP-47 (RFC 5646) parser whose
// `rawValue` keeps the wire string verbatim and acts as the single source of truth — parsed
// `Components` are never re-serialized back to an identifier.
//
// Scope: the canonical BCP-47 langtag grammar plus the RFC 5646 §2.2.8 grandfathered/irregular
// whitelist, in strict mode. The parser only validates grammar — it does not consult any subtag
// registry. Lenient mode is still syntax-only BCP-47 parsing: it does not accept `_` separators
// or perform canonicalization, but it skips RFC 5646 §4.1 duplicate-subtag value checks.
public struct Language: LexiconStringFormat {
  // The original wire string, kept verbatim (no normalization).
  public let rawValue: String
  // The BCP-47 parsed components (or grandfathered match).
  public let components: Components

  public init(string: String) throws {
    try self.init(string: string, strict: true)
  }

  // When `strict == false`, skips RFC 5646 §4.1 duplicate variant / extension-singleton
  // rejection; grammar, length cap, and ASCII charset gates still apply. Lenient instances
  // may therefore hold duplicate subtags — an invariant strict-parsed values never violate.
  public init(string: String, strict: Bool) throws {
    guard let components = Language.parse(string, strict: strict) else {
      throw LexiconStringFormatError.invalid(format: "language", value: string)
    }
    rawValue = string
    self.components = components
  }
}

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
    // BCP-47 §2.2.2 extended language subtags. Up to 3 `3ALPHA` subtags, only present when
    // the primary language is 2-3 ALPHA. Empty for tags without extlang. RFC 5646 discourages
    // the extlang form (`zh-cmn`) in favor of the primary subtag directly (`cmn`); the parser
    // accepts both forms verbatim and leaves canonicalization to the consumer.
    // The 3-ALPHA constraint is enforced by the parser (`isExtendedLanguageSubtag`), not by
    // the element type, which reuses `LanguageCode` (2-8 ALPHA) for shape parity.
    public let extendedLanguageSubtags: [LanguageCode]
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

extension Language {
  // Maximum byte length we accept for a single language identifier. BCP-47 itself has no upper
  // bound but ≤64 is a generous practical cap (real-world tags are ≤16 chars).
  private static let maxLength = 64

  // Precomputed lowercase rawValue → enum case map for O(1) grandfathered lookup.
  private static let grandfatheredLowercasedMap: [String: Grandfathered] =
    Dictionary(uniqueKeysWithValues: Grandfathered.allCases.map { ($0.rawValue.lowercased(), $0) })

  // Strict parser. Returns nil on any grammar or value violation; the caller wraps that in
  // `LexiconStringFormatError.invalid(format: "language", ...)`.
  static func parse(_ input: String) -> Components? {
    parse(input, strict: true)
  }

  // Shared parser. Strict mode also enforces RFC 5646 §4.1 duplicate variant / extension
  // singleton rejection. Lenient mode only checks well-formed syntax.
  static func parse(_ input: String, strict: Bool) -> Components? {
    guard !input.isEmpty, input.utf8.count <= maxLength else { return nil }
    for byte in input.utf8 where !isAllowedByte(byte) { return nil }

    // 1. Grandfathered/irregular: case-insensitive exact match.
    let lowered = input.lowercased()
    if let g = grandfatheredLowercasedMap[lowered] {
      return Components(
        languageCode: nil, extendedLanguageSubtags: [], script: nil, region: nil, variants: [],
        extensions: [], privateUse: [], grandfathered: g
      )
    }

    // 2. Split into subtags. Empty subtags (leading/trailing/duplicate `-`) → reject.
    let subtags = input.split(separator: "-", omittingEmptySubsequences: false)
    for tag in subtags where tag.isEmpty { return nil }

    // 3. Private-use-only tag (`x-…` / `X-…`).
    if subtags[0] == "x" || subtags[0] == "X" {
      let rest = subtags.dropFirst()
      guard !rest.isEmpty, rest.allSatisfy(isPrivateuseSubtag) else { return nil }
      return Components(
        languageCode: nil, extendedLanguageSubtags: [], script: nil, region: nil, variants: [],
        extensions: [], privateUse: rest.map(String.init), grandfathered: nil
      )
    }

    // 4. Langtag: language [-extlang] [-script] [-region] *[-variant] *[-extension] [-privateuse]
    var i = 0
    let n = subtags.count

    guard isLanguageSubtag(subtags[i]) else { return nil }
    let primary = subtags[i]
    let languageCode = LanguageCode(rawValue: String(primary))
    i += 1

    // RFC 5646 §2.2.2: extlang follows a 2-3 ALPHA primary subtag; up to 3 `3ALPHA` subtags.
    // Unlike variants and extension singletons, RFC 5646 §4.1's MUST-NOT duplicate rule does
    // not apply to extlang subtags; duplicates are accepted at the grammar level.
    var extendedLanguageSubtags: [LanguageCode] = []
    if primary.count <= 3 {
      while extendedLanguageSubtags.count < 3, i < n, isExtendedLanguageSubtag(subtags[i]) {
        extendedLanguageSubtags.append(LanguageCode(rawValue: String(subtags[i])))
        i += 1
      }
    }

    var script: Script?
    if i < n, isScriptSubtag(subtags[i]) {
      script = Script(rawValue: String(subtags[i]))
      i += 1
    }

    var region: Region?
    if i < n, isRegionSubtag(subtags[i]) {
      region = Region(rawValue: String(subtags[i]))
      i += 1
    }

    // RFC 5646 §4.1: "The same variant subtag MUST NOT be used more than once."
    // Comparison per §2.1.1 is case-insensitive.
    var variants: [Variant] = []
    var seenVariants: Set<String> = []
    while i < n, isVariantSubtag(subtags[i]) {
      if strict {
        let key = subtags[i].lowercased()
        guard seenVariants.insert(key).inserted else { return nil }
      }
      variants.append(Variant(rawValue: String(subtags[i])))
      i += 1
    }

    // RFC 5646 §4.1: "The same singleton MUST NOT be used more than once."
    var extensions: [Extension] = []
    var seenSingletons: Set<Character> = []
    while i < n, isExtensionSingleton(subtags[i]) {
      guard let singleton = subtags[i].first else { return nil }
      if strict {
        let key = Character(singleton.lowercased())
        guard seenSingletons.insert(key).inserted else { return nil }
      }
      i += 1
      var extSubtags: [String] = []
      while i < n, isExtensionSubtag(subtags[i]) {
        extSubtags.append(String(subtags[i]))
        i += 1
      }
      guard !extSubtags.isEmpty else { return nil }
      extensions.append(Extension(singleton: singleton, subtags: extSubtags))
    }

    var privateUse: [String] = []
    if i < n, subtags[i] == "x" || subtags[i] == "X" {
      i += 1
      while i < n, isPrivateuseSubtag(subtags[i]) {
        privateUse.append(String(subtags[i]))
        i += 1
      }
      guard !privateUse.isEmpty else { return nil }
    }

    guard i == n else { return nil }

    return Components(
      languageCode: languageCode, extendedLanguageSubtags: extendedLanguageSubtags,
      script: script, region: region,
      variants: variants, extensions: extensions, privateUse: privateUse,
      grandfathered: nil
    )
  }

  // Allowed bytes: ASCII letters, digits, and `-`.
  private static func isAllowedByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D: true
    default: false
    }
  }

  private static func isAlpha(_ s: Substring) -> Bool {
    !s.isEmpty
      && s.utf8.allSatisfy { (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }
  }

  private static func isDigit(_ s: Substring) -> Bool {
    !s.isEmpty && s.utf8.allSatisfy { (0x30...0x39).contains($0) }
  }

  private static func isAlphanum(_ s: Substring) -> Bool {
    !s.isEmpty
      && s.utf8.allSatisfy {
        (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
      }
  }

  // language: 2-3 ALPHA, 4 ALPHA reserved, or 5-8 ALPHA registered.
  private static func isLanguageSubtag(_ s: Substring) -> Bool {
    (2...8).contains(s.count) && isAlpha(s)
  }

  // extlang: exactly 3 ALPHA (follows a 2-3 ALPHA primary subtag).
  private static func isExtendedLanguageSubtag(_ s: Substring) -> Bool {
    s.count == 3 && isAlpha(s)
  }

  // script: 4 ALPHA.
  private static func isScriptSubtag(_ s: Substring) -> Bool {
    s.count == 4 && isAlpha(s)
  }

  // region: 2 ALPHA or 3 DIGIT.
  private static func isRegionSubtag(_ s: Substring) -> Bool {
    (s.count == 2 && isAlpha(s)) || (s.count == 3 && isDigit(s))
  }

  // variant: 5-8 alphanum, or DIGIT + 3 alphanum.
  private static func isVariantSubtag(_ s: Substring) -> Bool {
    if (5...8).contains(s.count), isAlphanum(s) { return true }
    if s.count == 4, let f = s.utf8.first, (0x30...0x39).contains(f), isAlphanum(s.dropFirst()) {
      return true
    }
    return false
  }

  // extension singleton: 1 alphanum, except `x` / `X` (reserved for privateuse).
  private static func isExtensionSingleton(_ s: Substring) -> Bool {
    s.count == 1 && isAlphanum(s) && s != "x" && s != "X"
  }

  // extension subtag: 2-8 alphanum.
  private static func isExtensionSubtag(_ s: Substring) -> Bool {
    (2...8).contains(s.count) && isAlphanum(s)
  }

  // privateuse subtag: 1-8 alphanum.
  private static func isPrivateuseSubtag(_ s: Substring) -> Bool {
    (1...8).contains(s.count) && isAlphanum(s)
  }
}
