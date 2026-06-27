import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringDIDTests {
  static let wire = "did:plc:7iza6de2dwap2sbkpav7c6c6"

  @Test func decodePreservesWireStringAndTypedYieldsDID() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<DID>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
    #expect(value.typed?.method == "plc")
  }

  @Test func invalidDIDDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not a did\"".utf8)
    let value = try JSONDecoder().decode(FormatString<DID>.self, from: data)
    #expect(value.rawValue == "not a did")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<DID>(rawValue: Self.wire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }

  @Test func initFromDIDPreservesWireString() throws {
    let did = try DID(string: Self.wire)
    let value = FormatString(did)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
  }

  @Test func decodesDIDFieldInRecord() throws {
    struct Record: Codable {
      var owner: FormatString<DID>
    }
    let json = Data("{\"owner\":\"\(Self.wire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.owner.rawValue == Self.wire)
    #expect(record.owner.typed?.method == "plc")
  }

  @Test func decodesDIDArrayFieldInRecord() throws {
    struct Record: Codable {
      var owners: [FormatString<DID>]
    }
    let json = Data("{\"owners\":[\"did:plc:abc\",\"did:web:example.com\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.owners.count == 2)
    #expect(record.owners.allSatisfy { $0.typed != nil })
  }

  @Test func decodesOversizedDIDWithNilTyped() throws {
    // Over the 2048 byte cap → strict parser rejects, lenient decode preserves rawValue.
    let identifier = String(repeating: "a", count: 2048 - 5)  // "did:m:" + body → 2049 byte
    let wire = "did:m:" + identifier
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<DID>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<DID>(rawValue: Self.wire)
    #expect(value.description == Self.wire)
  }
}
