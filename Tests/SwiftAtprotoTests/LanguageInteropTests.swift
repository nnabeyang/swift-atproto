import Foundation
import Testing

@testable import SwiftAtproto

// Valid/invalid BCP-47 (RFC 5646) vectors for the strict language parser. The `rawValue` is
// always preserved verbatim; sub-tags inside `Components` likewise keep the wire case.
struct LanguageInteropTests {
  static let validLanguages: [String] = [
    // 2-3 ALPHA primary language.
    "en", "EN", "en-US", "fr", "de", "ja", "zh", "cmn",
    // 4 ALPHA reserved + 5-8 ALPHA registered.
    "abcd", "abcde", "abcdefgh",
    // With script.
    "zh-Hant", "zh-Hans", "en-Latn", "sr-Cyrl",
    // With script and region.
    "zh-Hant-TW", "zh-Hans-CN", "en-Latn-US", "sr-Cyrl-RS",
    // With 3-digit UN M.49 region.
    "es-419", "en-001",
    // With variant subtags.
    "de-CH-1901", "sl-rozaj", "sl-rozaj-biske", "de-1996",
    // Variant of DIGIT + 3 alphanum.
    "en-1abc",
    // With Unicode/Locale extension (`u-…`).
    "en-US-u-islamcal", "de-DE-u-co-phonebk", "en-u-ca-buddhist-nu-thai",
    // Single-letter extension singletons other than `x`.
    "de-a-value", "en-r-extended-sequence",
    // Privateuse-only.
    "x-pig-latin", "X-Foo", "x-a-b-c", "x-1", "x-12345678",
    // With privateuse suffix on a langtag.
    "en-x-private", "de-CH-x-phonebk", "en-Latn-US-u-co-phonebk-x-twain",
    // Case preservation (wire form kept verbatim regardless of canonical case).
    "EN-us", "zh-hant", "DE-ch-1901",
    // Grandfathered / irregular (RFC 5646 §2.2.8) and their case variations.
    "i-klingon", "I-Klingon", "en-GB-oed", "EN-gb-OED", "sgn-BE-FR", "art-lojban",
    "no-bok", "zh-min-nan",
    // Extended language subtags (BCP-47 §2.2.2): up to 3 `3ALPHA` after a 2-3 ALPHA primary.
    "zh-cmn", "zh-yue-HK", "zh-cmn-Hans-CN", "ar-aao-Latn-DZ", "en-USA", "ab-bbb-cccc",
    "zh-cmn-cmn-cmn",
  ]

  static let invalidLanguages: [String] = [
    // Empty / pure hyphens.
    "", "-", "--", "---",
    // Empty subtags at edges or interior.
    "en-", "-en", "en--US", "en-US-",
    // No ALPHA in primary language.
    "1234", "12-US",
    // 1-char primary language (must be 2-8 ALPHA).
    "a", "1",
    // Wrong separator (BCP-47 uses `-`, not `_`).
    "en_US", "EN_us",
    // Trailing space / leading space / spurious whitespace.
    " en", "en ", "en US",
    // Non-ASCII bytes (Unicode letter, emoji).
    "ja-日本", "en-😀",
    // Privateuse degenerate forms (`x-` with no subtag, bare `x`).
    "x-", "x", "X",
    // Privateuse with overlong subtag (>8 alphanum) or empty subtag.
    "x-123456789", "x--foo",
    // Extension singleton without subtags.
    "en-a", "en-u", "en-u-", "en-u-x",
    // Extlang requires a 2-3 ALPHA primary subtag; reserved/registered primaries reject it.
    "abcd-xyz", "english-abc",
    // Extlang grammar caps at 3 subtags.
    "zh-cmn-cmn-cmn-cmn",
    // Region-shape only if 2 ALPHA or 3 DIGIT; 2-digit subtag is neither region nor variant.
    "en-12",
    // Length cap.
    String(repeating: "a", count: 65), "en-" + String(repeating: "a", count: 62),
  ]

  @Test(arguments: validLanguages)
  func validParses(_ tag: String) throws {
    let language = try Language(string: tag)
    #expect(language.rawValue == tag)
  }

  @Test(arguments: invalidLanguages)
  func invalidThrows(_ tag: String) {
    #expect(throws: (any Error).self) { try Language(string: tag) }
  }

  @Test func parsesVariantExtensionAndPrivateuse() throws {
    let l = try Language(string: "de-CH-1901-u-co-phonebk-x-private")
    #expect(l.rawValue == "de-CH-1901-u-co-phonebk-x-private")
    #expect(l.components.languageCode?.rawValue == "de")
    #expect(l.components.script == nil)
    #expect(l.components.region?.rawValue == "CH")
    #expect(l.components.variants.map(\.rawValue) == ["1901"])
    #expect(l.components.extensions.count == 1)
    #expect(l.components.extensions[0].singleton == "u")
    #expect(l.components.extensions[0].subtags == ["co", "phonebk"])
    #expect(l.components.privateUse == ["private"])
    #expect(l.components.grandfathered == nil)
  }

  @Test func parsesScriptRegionExtensionAndPrivateuse() throws {
    let l = try Language(string: "en-Latn-US-u-co-phonebk-x-twain")
    #expect(l.components.languageCode?.rawValue == "en")
    #expect(l.components.script?.rawValue == "Latn")
    #expect(l.components.region?.rawValue == "US")
    #expect(l.components.variants.isEmpty)
    #expect(l.components.extensions.count == 1)
    #expect(l.components.privateUse == ["twain"])
  }

  @Test func parsesPrivateuseOnly() throws {
    let l = try Language(string: "x-pig-latin")
    #expect(l.rawValue == "x-pig-latin")
    #expect(l.components.languageCode == nil)
    #expect(l.components.script == nil)
    #expect(l.components.region == nil)
    #expect(l.components.privateUse == ["pig", "latin"])
    #expect(l.components.grandfathered == nil)
  }

  @Test func preservesWireCaseInRawValueAndSubtags() throws {
    let l = try Language(string: "EN-us")
    #expect(l.rawValue == "EN-us")
    #expect(l.components.languageCode?.rawValue == "EN")
    #expect(l.components.region?.rawValue == "us")
  }

  @Test func multipleExtensionsAndVariants() throws {
    let l = try Language(string: "sl-rozaj-biske-u-co-standard-t-en-US")
    #expect(l.components.languageCode?.rawValue == "sl")
    #expect(l.components.variants.map(\.rawValue) == ["rozaj", "biske"])
    #expect(l.components.extensions.count == 2)
    #expect(l.components.extensions[0].singleton == "u")
    #expect(l.components.extensions[0].subtags == ["co", "standard"])
    #expect(l.components.extensions[1].singleton == "t")
    #expect(l.components.extensions[1].subtags == ["en", "US"])
  }

  @Test func parsesExtendedLanguageSubtag() throws {
    let l = try Language(string: "zh-cmn-Hans-CN")
    #expect(l.rawValue == "zh-cmn-Hans-CN")
    #expect(l.components.languageCode?.rawValue == "zh")
    #expect(l.components.extendedLanguageSubtags.map(\.rawValue) == ["cmn"])
    #expect(l.components.script?.rawValue == "Hans")
    #expect(l.components.region?.rawValue == "CN")
  }

  @Test func parsesMultipleExtendedLanguageSubtags() throws {
    let l = try Language(string: "zh-cmn-cmn-cmn")
    #expect(l.components.languageCode?.rawValue == "zh")
    #expect(l.components.extendedLanguageSubtags.map(\.rawValue) == ["cmn", "cmn", "cmn"])
    #expect(l.components.script == nil)
  }

  @Test func tagWithoutExtlangHasEmptySubtags() throws {
    let l = try Language(string: "zh-Hans-CN")
    #expect(l.components.languageCode?.rawValue == "zh")
    #expect(l.components.extendedLanguageSubtags.isEmpty)
    #expect(l.components.script?.rawValue == "Hans")
  }
}
