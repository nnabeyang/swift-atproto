import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringHandleTests {
  static let wire = "alice.example.com"

  @Test func decodePreservesWireStringAndTypedYieldsHandle() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Handle>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func invalidHandleDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not a handle\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Handle>.self, from: data)
    #expect(value.rawValue == "not a handle")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<Handle>(rawValue: Self.wire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromHandlePreservesWireString() throws {
    let handle = try Handle(string: Self.wire)
    let value = FormatString(handle)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesHandleFieldInRecord() throws {
    struct Record: Codable {
      var actor: FormatString<Handle>
    }
    let json = Data("{\"actor\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.actor.rawValue == Self.wire)
    #expect(record.actor.typed != nil)
  }

  @Test func decodesHandleArrayFieldInRecord() throws {
    struct Record: Codable {
      var handles: [FormatString<Handle>]
    }
    let json = Data("{\"handles\":[\"alice.example.com\",\"bob.example.org\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.handles.count == 2)
    #expect(record.handles.allSatisfy { $0.typed != nil })
  }

  @Test func decodesOversizedHandleWithNilTyped() throws {
    // Over the 253 byte cap → strict parser rejects, lenient decode preserves rawValue.
    let label63 = String(repeating: "a", count: 63)
    let label62 = String(repeating: "a", count: 62)
    let wire = "\(label63).\(label63).\(label63).\(label62)"  // 254 byte
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<Handle>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<Handle>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
  }
}
