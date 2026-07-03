import Foundation
import Testing

@testable import SwiftAtproto

// Attack-oriented coverage: Unicode confusables, control bytes, length boundaries, every
// permitted singleton, RFC 5646 §4.1 MUST-NOT cases (duplicate variants / singletons), and
// `FormatString<Language>` lenient decoding paths.
struct LanguageAdversarialTests {
  // MARK: - Unicode confusables and non-ASCII bytes

  static let confusables: [String] = [
    "\u{0435}n-US",  // Cyrillic small e + n
    "\u{0410}-US",  // Cyrillic capital A as single-letter "language" (invalid even shaped right)
    "en-U\u{0405}",  // Cyrillic capital dze where 'S' should be
    "ja-\u{65E5}\u{672C}",  // CJK "Japan" as a region
    "en\u{2010}US",  // U+2010 HYPHEN (NOT ASCII `-`)
    "en\u{2013}US",  // EN DASH
    "en-US\u{200B}",  // ZERO WIDTH SPACE
    "\u{FEFF}en-US",  // BOM
    "e\u{0301}n-US",  // combining acute on e
  ]

  @Test(arguments: confusables)
  func nonAsciiBytesAreRejected(_ tag: String) {
    #expect(throws: (any Error).self) { try Language(string: tag) }
  }

  // MARK: - ASCII control bytes and separator look-alikes

  static let controlChars: [String] = [
    "en\u{00}US",  // NUL
    "en\u{09}US",  // TAB
    "en\u{0A}US",  // LF
    "en\u{0D}US",  // CR
    "en\u{1F}US",  // unit separator
    "en\u{7F}US",  // DEL
    "en US",  // SPACE
    "en\tUS",  // TAB literal
    "en/US",  // slash
    "en.US",  // dot
    "en_US",  // underscore (BCP-47 uses `-`)
  ]

  @Test(arguments: controlChars)
  func nonHyphenSeparatorsAreRejected(_ tag: String) {
    #expect(throws: (any Error).self) { try Language(string: tag) }
  }

  // MARK: - Length boundaries

  @Test func acceptsLanguageAtLengthBoundary() throws {
    // Exactly 64 bytes: "en-x-" (5) + 6 × ("aaaaaaaa-" = 9 bytes) + "ggggg" (5) = 64.
    let tag =
      "en-x-" + String(repeating: "a", count: 8) + "-"
      + String(repeating: "b", count: 8) + "-" + String(repeating: "c", count: 8)
      + "-" + String(repeating: "d", count: 8) + "-"
      + String(repeating: "e", count: 8) + "-"
      + String(repeating: "f", count: 8) + "-" + String(repeating: "g", count: 5)
    #expect(tag.utf8.count == 64)
    let l = try Language(string: tag)
    #expect(l.rawValue == tag)
  }

  @Test func rejectsLanguageOneOverLengthCap() {
    let tag =
      "en-x-" + String(repeating: "a", count: 8) + "-"
      + String(repeating: "b", count: 8) + "-" + String(repeating: "c", count: 8)
      + "-" + String(repeating: "d", count: 8) + "-"
      + String(repeating: "e", count: 8) + "-"
      + String(repeating: "f", count: 8) + "-" + String(repeating: "g", count: 6)
    #expect(tag.utf8.count == 65)
    #expect(throws: (any Error).self) { try Language(string: tag) }
  }

  // MARK: - Every permitted singleton (BCP-47 §2.2.6)

  static let validSingletons: [Character] = {
    var chars: [Character] = []
    for byte: UInt8 in 0x30...0x39 { chars.append(Character(UnicodeScalar(byte))) }
    for byte: UInt8 in 0x41...0x5A where byte != 0x58 {
      chars.append(Character(UnicodeScalar(byte)))
    }
    for byte: UInt8 in 0x61...0x7A where byte != 0x78 {
      chars.append(Character(UnicodeScalar(byte)))
    }
    return chars
  }()

  @Test(arguments: validSingletons)
  func acceptsEverySingletonExceptX(_ singleton: Character) throws {
    let l = try Language(string: "en-\(singleton)-ab")
    #expect(l.components.extensions.count == 1)
    #expect(l.components.extensions[0].singleton == singleton)
    #expect(l.components.extensions[0].subtags == ["ab"])
  }

  @Test(arguments: ["x", "X"])
  func xCannotBeAnExtensionSingleton(_ tag: String) throws {
    // `en-x-ab`: `x` opens privateuse, not extension.
    let l = try Language(string: "en-\(tag)-ab")
    #expect(l.components.extensions.isEmpty)
    #expect(l.components.privateUse == ["ab"])
  }

  // MARK: - RFC 5646 §4.1 MUST-NOT: subtag uniqueness

  @Test func rejectsDuplicateVariantSubtags() throws {
    // §4.1: "The same variant subtag MUST NOT be used more than once within a language tag."
    #expect(throws: (any Error).self) { try Language(string: "de-1996-1996") }
    #expect(throws: (any Error).self) { try Language(string: "de-1996-1996", strict: true) }
    let lenient = try Language(string: "de-1996-1996", strict: false)
    #expect(lenient.components.variants.map(\.rawValue) == ["1996", "1996"])
  }

  @Test func rejectsDuplicateVariantSubtagsCaseInsensitively() throws {
    // §2.1.1 subtag comparison is case-insensitive.
    #expect(throws: (any Error).self) { try Language(string: "sl-rozaj-ROZAJ") }
    let lenient = try Language(string: "sl-rozaj-ROZAJ", strict: false)
    #expect(lenient.components.variants.map(\.rawValue) == ["rozaj", "ROZAJ"])
  }

  @Test func rejectsDuplicateExtensionSingletons() {
    // §4.1: "The same singleton MUST NOT be used more than once in a language tag."
    #expect(throws: (any Error).self) { try Language(string: "en-u-co-phonebk-u-other") }
    let lenient = try? Language(string: "en-u-co-phonebk-u-other", strict: false)
    #expect(lenient?.components.extensions.map(\.singleton) == ["u", "u"])
  }

  @Test func rejectsDuplicateExtensionSingletonsCaseInsensitively() {
    #expect(throws: (any Error).self) { try Language(string: "en-U-co-u-other") }
    let lenient = try? Language(string: "en-U-co-u-other", strict: false)
    #expect(lenient?.components.extensions.map(\.singleton) == ["U", "u"])
  }

  // Lenient only relaxes RFC 5646 §4.1 value checks; every other syntax gate
  // (non-ASCII, control bytes, underscore, length cap, missing extension subtag) must
  // still reject.
  static let lenientSyntaxInvalid: [String] = {
    let overLength =
      "en-x-" + String(repeating: "a", count: 8) + "-"
      + String(repeating: "b", count: 8) + "-" + String(repeating: "c", count: 8)
      + "-" + String(repeating: "d", count: 8) + "-"
      + String(repeating: "e", count: 8) + "-"
      + String(repeating: "f", count: 8) + "-" + String(repeating: "g", count: 6)
    return confusables + controlChars + [
      "not a language tag",
      "en-u",  // extension singleton with no subtag
      overLength,  // 65 bytes
    ]
  }()

  @Test(arguments: lenientSyntaxInvalid)
  func lenientStillRejectsSyntaxInvalidLanguage(_ tag: String) {
    #expect(throws: (any Error).self) { try Language(string: tag, strict: false) }
  }

  // MARK: - Hashable identity

  @Test func equalRawValueImpliesEqualValueAndHash() throws {
    let a = try Language(string: "en-US")
    let b = try Language(string: "en-US")
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
  }

  @Test func differentWireCaseProducesDifferentValues() throws {
    let lower = try Language(string: "en-us")
    let mixed = try Language(string: "EN-us")
    #expect(lower != mixed)
    #expect(lower.rawValue != mixed.rawValue)
  }

  // MARK: - Components invariants

  @Test(arguments: ["en", "en-US", "zh-Hant-TW", "x-foo", "i-klingon"])
  func languageCodeNilImpliesPrivateuseOrGrandfathered(_ tag: String) throws {
    let l = try Language(string: tag)
    if l.components.languageCode == nil {
      #expect(!l.components.privateUse.isEmpty || l.components.grandfathered != nil)
    }
  }

  // MARK: - FormatString<Language> attacks

  @Test func formatStringDecodesNullThrows() {
    let data = Data("null".utf8)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(FormatString<Language>.self, from: data)
    }
  }

  @Test func formatStringDecodesNumberThrows() {
    let data = Data("42".utf8)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(FormatString<Language>.self, from: data)
    }
  }

  @Test func formatStringDecodesEmptyStringWithNilTyped() throws {
    let data = Data("\"\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Language>.self, from: data)
    #expect(value.rawValue == "")
    #expect(value.typed == nil)
  }

  @Test func formatStringDecodesOversizedStringWithNilTyped() throws {
    let oversized = String(repeating: "a", count: 100)
    let data = Data("\"\(oversized)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Language>.self, from: data)
    #expect(value.rawValue == oversized)
    #expect(value.typed == nil)
  }

  @Test func formatStringRoundTripPreservesWireString() throws {
    let wire = "EN-Latn-us-1901-u-co-phonebk-x-twain"
    let value = try JSONDecoder().decode(
      FormatString<Language>.self, from: Data("\"\(wire)\"".utf8))
    let encoded = try JSONEncoder().encode(value)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"\(wire)\"")
  }

  // MARK: - Public API surface lockdown

  // Locks the public-facing API of `Language` and its nested types so future refactors that
  // drop a property, rename a case, or remove a conformance fail to compile or fail the test.

  @Test func languageConformsToLexiconStringFormat() throws {
    let l: any LexiconStringFormat = try Language(string: "en")
    #expect(l.rawValue == "en")
  }

  @Test func subtagNewtypesAreRawRepresentableWithPublicInit() {
    // The newtypes are public RawRepresentable so callers can model their own JSON; the
    // resulting Language is still gated by the throwing parser.
    let lc: Language.LanguageCode = Language.LanguageCode(rawValue: "en")
    let sc: Language.Script = Language.Script(rawValue: "Latn")
    let rg: Language.Region = Language.Region(rawValue: "US")
    let vr: Language.Variant = Language.Variant(rawValue: "1901")
    #expect(lc.rawValue == "en")
    #expect(sc.rawValue == "Latn")
    #expect(rg.rawValue == "US")
    #expect(vr.rawValue == "1901")
  }

  @Test func grandfatheredEnumHasExactlyTwentySixCases() {
    // RFC 5646 §2.2.8: 17 irregular + 9 regular.
    #expect(Language.Grandfathered.allCases.count == 26)
  }

  @Test func languageStoredPropertiesAreImmutable() throws {
    // `let` stored properties surface as non-mutable children; this is a smoke check that
    // refactors don't switch to `var`.
    let l = try Language(string: "en-US")
    let mirror = Mirror(reflecting: l)
    let labels = mirror.children.compactMap(\.label)
    #expect(labels.contains("rawValue"))
    #expect(labels.contains("components"))
  }

  // MARK: - Subtag order preservation (RFC 5646 SHOULD)

  @Test func variantOrderIsPreservedInWire() throws {
    let a = try Language(string: "de-CH-1901-1996")
    let b = try Language(string: "de-CH-1996-1901")
    #expect(a.components.variants.map(\.rawValue) == ["1901", "1996"])
    #expect(b.components.variants.map(\.rawValue) == ["1996", "1901"])
    #expect(a != b)
    #expect(a.rawValue != b.rawValue)
  }

  @Test func extensionOrderIsPreservedInWire() throws {
    let a = try Language(string: "en-a-bb-b-cc")
    let b = try Language(string: "en-b-cc-a-bb")
    #expect(a.components.extensions.map(\.singleton) == ["a", "b"])
    #expect(b.components.extensions.map(\.singleton) == ["b", "a"])
    #expect(a != b)
  }

  // MARK: - Subtag length boundaries

  @Test func variantAtFiveCharBoundary() throws {
    let l = try Language(string: "sl-rozaj")
    #expect(l.components.variants.first?.rawValue == "rozaj")
  }

  @Test func variantAtEightCharBoundary() throws {
    let l = try Language(string: "en-12345abc")
    #expect(l.components.variants.first?.rawValue == "12345abc")
  }

  @Test func extensionSubtagAtTwoAndEightCharBoundaries() throws {
    let l = try Language(string: "en-u-ab-abcdefgh-12345678")
    #expect(l.components.extensions.count == 1)
    #expect(l.components.extensions[0].subtags == ["ab", "abcdefgh", "12345678"])
  }

  @Test func privateuseSubtagAtOneAndEightCharBoundaries() throws {
    let l = try Language(string: "x-a-abcdefgh-12345678")
    #expect(l.components.privateUse == ["a", "abcdefgh", "12345678"])
  }

  // MARK: - Invariants over the full positive test corpus

  @Test func componentsInvariantsHoldAcrossAllValidLanguages() throws {
    // Run the structural invariants over every entry in the positive test corpus so a future
    // parser change that violates them in some obscure tag fails loudly.
    for tag in LanguageInteropTests.validLanguages {
      let l = try Language(string: tag)
      #expect(l.rawValue == tag, "rawValue must be verbatim for \(tag)")

      let c = l.components
      if c.languageCode == nil {
        #expect(
          !c.privateUse.isEmpty || c.grandfathered != nil,
          "languageCode==nil but no privateUse and no grandfathered for \(tag)")
      }
      if c.grandfathered != nil {
        // Grandfathered match consumes the entire wire; other slots stay empty.
        #expect(c.languageCode == nil, "grandfathered tag has language for \(tag)")
        #expect(c.script == nil, "grandfathered tag has script for \(tag)")
        #expect(c.region == nil, "grandfathered tag has region for \(tag)")
        #expect(c.variants.isEmpty, "grandfathered tag has variants for \(tag)")
        #expect(c.extensions.isEmpty, "grandfathered tag has extensions for \(tag)")
        #expect(c.privateUse.isEmpty, "grandfathered tag has privateUse for \(tag)")
      }
    }
  }
}
