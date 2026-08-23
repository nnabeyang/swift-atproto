import Foundation
import Testing

@testable import SwiftAtproto

struct LexSpaceTests {
  @Test func recordKeyTypeKnownConstantsRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for value in [LexRecordKeyType.any, .nsid, .tid] {
      let data = try encoder.encode(value)
      #expect(String(data: data, encoding: .utf8) == "\"\(value.rawValue)\"")
      let decoded = try decoder.decode(LexRecordKeyType.self, from: data)
      #expect(decoded == value)
    }
  }

  @Test func recordKeyTypePreservesUnknownRawValue() throws {
    let data = Data("\"bogus\"".utf8)
    let decoded = try JSONDecoder().decode(LexRecordKeyType.self, from: data)
    #expect(decoded.rawValue == "bogus")
    #expect(decoded != .any)
    #expect(decoded.literalValue == nil)

    let reEncoded = try JSONEncoder().encode(decoded)
    #expect(String(data: reEncoded, encoding: .utf8) == "\"bogus\"")
  }

  @Test func literalKeyTypeRoundTripsThroughItsPayload() {
    let key = LexRecordKeyType.literal("self")
    #expect(key.rawValue == "literal:self")
    #expect(key.literalValue == "self")
  }

  @Test func knownKeyTypesHaveNoLiteralPayload() {
    #expect(LexRecordKeyType.any.literalValue == nil)
    #expect(LexRecordKeyType.nsid.literalValue == nil)
    #expect(LexRecordKeyType.tid.literalValue == nil)
  }

  // A bare `literal:` names no value, so it reads back as no payload rather
  // than as an empty one.
  @Test func emptyLiteralPayloadReadsAsNil() {
    #expect(LexRecordKeyType(rawValue: "literal:").literalValue == nil)
  }

  @Test func conformingTypeSatisfiesProtocol() {
    #expect(SampleForumSpace.id == "com.example.forum")
    #expect(SampleForumSpace.key == .any)
    #expect(SampleForumSpace.name == "Example Forum")
    #expect(SampleForumSpace.nameLang?["ja"] == "サンプル掲示板")
    #expect(SampleForumSpace.collections.count == 1)
    #expect(SampleForumSpace.collections[0].typed?.rawValue == "com.example.thread")
    #expect(SampleForumSpace.description == nil)
  }

  // A collection that is not a well-formed NSID still round-trips as a wire
  // string; only `typed` reports the problem.
  @Test func malformedCollectionKeepsItsWireString() {
    let collection = FormatString<NSID>(rawValue: "not-a-valid-nsid")
    #expect(collection.rawValue == "not-a-valid-nsid")
    #expect(collection.typed == nil)
  }
}

private enum SampleForumSpace: LexSpace {
  static let id = "com.example.forum"
  static let key: LexRecordKeyType = .any
  static let name: String = "Example Forum"
  static let nameLang: [String: String]? = ["ja": "サンプル掲示板"]
  static let collections: [FormatString<NSID>] = [
    FormatString<NSID>(rawValue: "com.example.thread")
  ]
  static let description: String? = nil
}
