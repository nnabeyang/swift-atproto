import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringTIDTests {
  static let wire = "3jzfcijpj2z2a"

  @Test func decodePreservesWireStringAndTypedYieldsTID() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<TID>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func invalidTIDDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not-a-tid\"".utf8)
    let value = try JSONDecoder().decode(FormatString<TID>.self, from: data)
    #expect(value.rawValue == "not-a-tid")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<TID>(rawValue: Self.wire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromTIDPreservesWireString() throws {
    let tid = try TID(string: Self.wire)
    let value = FormatString(tid)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesTIDFieldInRecord() throws {
    struct Record: Codable {
      var ts: FormatString<TID>
    }
    let json = Data("{\"ts\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.ts.rawValue == Self.wire)
    #expect(record.ts.typed != nil)
  }

  @Test func decodesTIDArrayFieldInRecord() throws {
    struct Record: Codable {
      var timestamps: [FormatString<TID>]
    }
    let json = Data("{\"timestamps\":[\"3jzfcijpj2z2a\",\"3kbgyjzqfeq2e\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.timestamps.count == 2)
    #expect(record.timestamps.allSatisfy { $0.typed != nil })
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<TID>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
  }

  @Test func generatorOutputRoundTripsThroughFormatString() throws {
    let tid = TID.next()
    let value = FormatString(tid)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(FormatString<TID>.self, from: data)
    #expect(decoded.rawValue == tid.rawValue)
    #expect(decoded.typed?.rawValue == tid.rawValue)
    #expect(decoded.typed?.timestamp == tid.timestamp)
    #expect(decoded.typed?.clockId == tid.clockId)
  }
}
