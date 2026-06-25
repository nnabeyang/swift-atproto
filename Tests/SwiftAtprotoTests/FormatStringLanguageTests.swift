import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringLanguageTests {
  static let wire = "en-US"

  @Test func decodePreservesWireStringAndTypedYieldsLanguage() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Language>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
    #expect(value.typed?.components.languageCode?.rawValue == "en")
    #expect(value.typed?.components.region?.rawValue == "US")
  }

  @Test func invalidLanguageDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not a language tag\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Language>.self, from: data)
    #expect(value.rawValue == "not a language tag")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<Language>(rawValue: Self.wire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromLanguagePreservesWireString() throws {
    let lang = try Language(string: "zh-Hant-TW")
    let value = FormatString(lang)
    #expect(value.rawValue == "zh-Hant-TW")
    #expect(value.typed?.components.languageCode?.rawValue == "zh")
    #expect(value.typed?.components.script?.rawValue == "Hant")
    #expect(value.typed?.components.region?.rawValue == "TW")
  }

  @Test func decodesArrayOfLanguageFieldsInRecord() throws {
    struct Post: Codable {
      var langs: [FormatString<Language>]
    }
    let json = Data("{\"langs\":[\"en\",\"es-419\",\"x-pig-latin\"]}".utf8)
    let post = try JSONDecoder().decode(Post.self, from: json)
    #expect(post.langs.map(\.rawValue) == ["en", "es-419", "x-pig-latin"])
    #expect(post.langs.allSatisfy { $0.typed != nil })
  }

  @Test func decodesGrandfatheredFieldInRecord() throws {
    struct Record: Codable {
      var lang: FormatString<Language>
    }
    let json = Data("{\"lang\":\"i-klingon\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.lang.rawValue == "i-klingon")
    #expect(record.lang.typed?.components.grandfathered == .iKlingon)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<Language>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
    #expect("\(value)" == Self.wire)
  }
}
