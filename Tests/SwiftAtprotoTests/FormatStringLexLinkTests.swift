import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringLexLinkTests {
  // Known-answer vectors: the CID of SHA-256("hello world").
  //   mh = Multihash(raw: "hello world", hashedWith: .sha2_256)
  //   cidV0 = CID(version: .v0, codec: .dag_pb, multihash: mh).toBaseEncodedString
  //   cidV1 = CID(version: .v1, codec: .raw,    multihash: mh).toBaseEncodedString
  static let cidV0 = "QmaozNR7DZHQK1ZcU9p7QdrshMvXqWK6gpu5rmrkPdT3L4"
  static let cidV1 = "bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"

  @Test func cidStringRoundTrips() throws {
    #expect(try LexLink(string: Self.cidV0).rawValue == Self.cidV0)
    #expect(try LexLink(string: Self.cidV1).rawValue == Self.cidV1)
  }

  @Test func invalidCidThrows() {
    #expect(throws: (any Error).self) {
      try LexLink(string: "QmdfTbBqBPQ7VNxZEYEj14VmRuZBkqFbiwReogJgS1zIII")
    }
    #expect(throws: (any Error).self) { try LexLink(string: "not-a-cid") }
  }

  @Test func decodePreservesWireStringAndTypedYieldsCID() throws {
    let data = Data("\"\(Self.cidV1)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<LexLink>.self, from: data)
    #expect(value.rawValue == Self.cidV1)
    #expect(value.typed?.rawValue == Self.cidV1)
  }

  @Test func invalidCidDecodesLenientlyWithNilTyped() throws {
    let data = Data("\"not-a-cid\"".utf8)
    let value = try JSONDecoder().decode(FormatString<LexLink>.self, from: data)
    #expect(value.rawValue == "not-a-cid")
    #expect(value.typed == nil)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<LexLink>(rawValue: Self.cidV0)
    let data = try JSONEncoder().encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.cidV0)\"")
  }

  @Test func initFromLexLinkUsesCanonicalRawValue() throws {
    let cid = try LexLink(string: Self.cidV1)
    let value = FormatString(cid)
    #expect(value.rawValue == Self.cidV1)
    #expect(value.typed?.rawValue == Self.cidV1)
  }

  @Test func decodesLexLinkFieldInRecord() throws {
    struct Record: Codable {
      var ref: FormatString<LexLink>
    }
    let json = Data("{\"ref\":\"\(Self.cidV0)\"}".utf8)
    let record = try JSONDecoder().decode(Record.self, from: json)
    #expect(record.ref.rawValue == Self.cidV0)
    #expect(record.ref.typed != nil)
  }

  @Test func descriptionIsRawValue() {
    let value = FormatString<LexLink>(rawValue: Self.cidV0)
    #expect(value.description == Self.cidV0)
    #expect("\(value)" == Self.cidV0)
  }
}
