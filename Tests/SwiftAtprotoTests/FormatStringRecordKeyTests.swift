import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringRecordKeyTests {
  static let wire = "3jzfcijpj2z2a"

  @Test func decodePreservesWireStringAndTypedYieldsRecordKey() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<RecordKey>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func invalidRecordKeyDecodesLenientlyWithNilTyped() throws {
    let data = Data("\".\"".utf8)  // forbidden value
    let value = try JSONDecoder().decode(FormatString<RecordKey>.self, from: data)
    #expect(value.rawValue == ".")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<RecordKey>(rawValue: Self.wire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromRecordKeyPreservesWireString() throws {
    let rkey = try RecordKey(string: Self.wire)
    let value = FormatString(rkey)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesRecordKeyFieldInRecord() throws {
    struct Record: Codable {
      var rkey: FormatString<RecordKey>
    }
    let json = Data("{\"rkey\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.rkey.rawValue == Self.wire)
    #expect(record.rkey.typed != nil)
  }

  @Test func decodesRecordKeyArrayFieldInRecord() throws {
    struct Record: Codable {
      var rkeys: [FormatString<RecordKey>]
    }
    let json = Data("{\"rkeys\":[\"self\",\"3jzfcijpj2z2a\",\"abc-def\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.rkeys.count == 3)
    #expect(record.rkeys.allSatisfy { $0.typed != nil })
  }

  @Test func decodesOversizedRecordKeyWithNilTyped() throws {
    // Over the 512 byte cap → strict parser rejects, lenient decode preserves rawValue.
    let wire = String(repeating: "a", count: 513)
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<RecordKey>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<RecordKey>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
  }
}
