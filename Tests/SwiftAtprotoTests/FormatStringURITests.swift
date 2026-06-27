import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringURITests {
  static let wire = "https://example.com/path?q=1#frag"

  @Test func decodePreservesWireStringAndTypedYieldsURI() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<URI>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
    #expect(value.typed?.scheme == "https")
  }

  @Test func invalidURIDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not a uri\"".utf8)
    let value = try JSONDecoder().decode(FormatString<URI>.self, from: data)
    #expect(value.rawValue == "not a uri")
    #expect(value.typed == nil)
  }

  @Test func atURIDecodesAsValidURI() throws {
    // `uri` is the broader format and should accept AT URIs alongside other schemes.
    let wire = "at://did:plc:abc/com.example.foo/rkey"
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<URI>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed?.scheme == "at")
    #expect(value.typed?.atUri != nil)
    #expect(value.typed?.url() == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<URI>(rawValue: Self.wire)
    let encoder = JSONEncoder()
    // The wire string contains "/", which JSONEncoder escapes to "\/" by default.
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromURIPreservesWireString() throws {
    let uri = try URI(string: Self.wire)
    let value = FormatString(uri)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesURIFieldInRecord() throws {
    struct Record: Codable {
      var link: FormatString<URI>
    }
    let json = Data("{\"link\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.link.rawValue == Self.wire)
    #expect(record.link.typed?.scheme == "https")
  }

  @Test func decodesURIArrayFieldInRecord() throws {
    struct Record: Codable {
      var links: [FormatString<URI>]
    }
    let json = Data("{\"links\":[\"https://a.example\",\"at://did:plc:abc\",\"did:web:x\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.links.count == 3)
    #expect(record.links.map(\.rawValue) == ["https://a.example", "at://did:plc:abc", "did:web:x"])
    #expect(record.links.allSatisfy { $0.typed != nil })
  }

  @Test func decodesOversizedURIWithNilTyped() throws {
    // Over the 8 KiB cap → strict parser rejects, lenient decode preserves rawValue.
    let body = String(repeating: "a", count: 8 * 1024)
    let wire = "https:" + body
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<URI>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<URI>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
    #expect("\(value)" == Self.wire)
  }
}
