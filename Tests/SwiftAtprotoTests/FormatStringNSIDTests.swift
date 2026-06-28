import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringNSIDTests {
  static let wire = "com.example.foo"

  @Test func decodePreservesWireStringAndTypedYieldsNSID() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<NSID>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
    #expect(value.typed?.authority == "example.com")
    #expect(value.typed?.name == "foo")
  }

  @Test func invalidNSIDDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not.an.0nsid\"".utf8)  // last segment starts with digit
    let value = try JSONDecoder().decode(FormatString<NSID>.self, from: data)
    #expect(value.rawValue == "not.an.0nsid")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<NSID>(rawValue: Self.wire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromNSIDPreservesWireString() throws {
    let nsid = try NSID(string: Self.wire)
    let value = FormatString(nsid)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesNSIDFieldInRecord() throws {
    struct Record: Codable {
      var collection: FormatString<NSID>
    }
    let json = Data("{\"collection\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.collection.rawValue == Self.wire)
    #expect(record.collection.typed?.name == "foo")
  }

  @Test func decodesNSIDArrayFieldInRecord() throws {
    struct Record: Codable {
      var collections: [FormatString<NSID>]
    }
    let json = Data("{\"collections\":[\"com.example.feed.post\",\"net.example.repo.createRecord\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.collections.count == 2)
    #expect(record.collections.allSatisfy { $0.typed != nil })
  }

  @Test func decodesOversizedNSIDWithNilTyped() throws {
    // Over the 317 byte cap → strict parser rejects, lenient decode preserves rawValue.
    let label63 = String(repeating: "a", count: 63)
    let label62 = String(repeating: "a", count: 62)
    let wire = "\(label63).\(label63).\(label63).\(label63).\(label62)"  // 318 byte
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<NSID>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<NSID>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
  }
}
