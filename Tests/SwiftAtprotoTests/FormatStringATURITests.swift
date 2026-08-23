import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringATURITests {
  static let wire = "at://did:plc:asdf123/com.atproto.feed.post/record"

  @Test func decodePreservesWireStringAndTypedYieldsATURI() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<ATURI>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func invalidATURIDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not-an-at-uri\"".utf8)
    let value = try JSONDecoder().decode(FormatString<ATURI>.self, from: data)
    #expect(value.rawValue == "not-an-at-uri")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<ATURI>(rawValue: Self.wire)
    let encoder = JSONEncoder()
    // The wire string contains "/", which JSONEncoder escapes to "\/" by default.
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromATURIUsesCanonicalRawValue() throws {
    let aturi = try ATURI(string: Self.wire)
    let value = FormatString(aturi)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesATURIFieldInRecord() throws {
    struct Record: Codable {
      var subject: FormatString<ATURI>
    }
    let json = Data("{\"subject\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.subject.rawValue == Self.wire)
    #expect(record.subject.typed != nil)
  }

  @Test func typedIsNilButTypedLenientIsNonNilForTrailingSlash() throws {
    let wire = "at://did:plc:asdf123/com.atproto.feed.post/"
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<ATURI>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
    #expect(value.typedLenient != nil)
  }

  @Test func typedIsNilButTypedLenientIsNonNilForForbiddenRkey() throws {
    let wire = "at://did:plc:asdf123/com.atproto.feed.post/.."
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<ATURI>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
    #expect(value.typedLenient != nil)
    #expect(value.typedLenient?.rkey?.rawValue == "..")
  }

  // A space record URI is what the alpha `com.atproto.space` methods return in their `at-uri`
  // fields. Before space support it decoded fine but degraded to a nil `typed`, leaving the
  // caller unable to read the record it names.
  @Test func spaceRecordURIIsTyped() throws {
    let wire =
      "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/com.atproto.feed.post/abc123"
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<ATURI>.self, from: data)
    #expect(value.rawValue == wire)
    let typed = try #require(value.typed)
    #expect(typed.isSpace)
    #expect(typed.collection?.rawValue == "com.atproto.feed.post")
    #expect(typed.rkey?.rawValue == "abc123")
    #expect(typed.spaceRef?.rawValue == "at://did:plc:asdf123/space/com.example.group/default")
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<ATURI>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
    #expect("\(value)" == Self.wire)
  }
}
