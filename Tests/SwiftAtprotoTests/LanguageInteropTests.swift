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

  @Test(arguments: validLanguages)
  func validParses(_ tag: String) throws {
    let language = try Language(string: tag)
    #expect(language.rawValue == tag)
  }
}
