import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringAtIdentifierTests {
  static let didWire = "did:plc:7iza6de2dwap2sbkpav7c6c6"
  static let handleWire = "alice.example.com"

  @Test func decodeDIDPreservesWireAndTypedDispatchesToDIDCase() throws {
    let data = Data("\"\(Self.didWire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<AtIdentifier>.self, from: data)
    #expect(value.rawValue == Self.didWire)
    if case .did(let d) = value.typed {
      #expect(d.rawValue == Self.didWire)
    } else {
      Issue.record("expected .did variant")
    }
  }

  @Test func decodeHandlePreservesWireAndTypedDispatchesToHandleCase() throws {
    let data = Data("\"\(Self.handleWire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<AtIdentifier>.self, from: data)
    #expect(value.rawValue == Self.handleWire)
    if case .handle(let h) = value.typed {
      #expect(h.rawValue == Self.handleWire)
    } else {
      Issue.record("expected .handle variant")
    }
  }

  @Test func invalidAtIdentifierDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"did:invalid:\"".utf8)
    let value = try JSONDecoder().decode(FormatString<AtIdentifier>.self, from: data)
    #expect(value.rawValue == "did:invalid:")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireStringForDID() throws {
    let value = FormatString<AtIdentifier>(rawValue: Self.didWire)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.didWire)\"")
  }

  @Test func initFromAtIdentifierPreservesWireString() throws {
    let id = try AtIdentifier(string: Self.handleWire)
    let value = FormatString(id)
    #expect(value.rawValue == Self.handleWire)
    #expect(value.typed?.rawValue == Self.handleWire)
  }

  @Test func decodesAtIdentifierFieldInRecord() throws {
    struct Record: Codable {
      var actor: FormatString<AtIdentifier>
    }
    let json = Data("{\"actor\":\"\(Self.handleWire)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.actor.rawValue == Self.handleWire)
    #expect(record.actor.typed != nil)
  }

  @Test func decodesAtIdentifierArrayFieldInRecord() throws {
    struct Record: Codable {
      var actors: [FormatString<AtIdentifier>]
    }
    let json = Data("{\"actors\":[\"did:plc:abc\",\"alice.test\",\"bob.example.com\"]}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.actors.count == 3)
    #expect(record.actors.allSatisfy { $0.typed != nil })
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<AtIdentifier>(rawValue: Self.didWire)
    #expect(value.description == Self.didWire)
  }
}
