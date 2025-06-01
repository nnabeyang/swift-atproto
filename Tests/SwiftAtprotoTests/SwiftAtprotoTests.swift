import CID
import Foundation
import Multicodec
import Multihash
import XCTest
@testable import SwiftAtproto

struct XRPCTestClient: XRPCClientProtocol {
    var serviceEndpoint: URL

    var decoder: JSONDecoder

    var auth: any XRPCAuth

    func tokenIsExpired(error _: SwiftAtproto.UnExpectedError) -> Bool {
        fatalError()
    }

    func getAuthorization(endpoint _: String) -> String? {
        fatalError()
    }

    func refreshSession() async -> Bool {
        fatalError()
    }

    func signout() {
        fatalError()
    }
}

final class SwiftAtprotoTests: XCTestCase {
    func testURLAppendPercentEncodedQueryItems() {
        var url = URL(string: "https://example.com")!
        url.append(percentEncodedQueryItems: [.init(name: #"%3B%2C%2F%3F%3A%40%26%3D%2B%24%23-"#, value: #"_.%21%7E%2A%27%28%29%5B%5D"#)])
        XCTAssertEqual(url.absoluteString, "https://example.com?%3B%2C%2F%3F%3A%40%26%3D%2B%24%23-=_.%21%7E%2A%27%28%29%5B%5D")
    }

    func testMakeParameters() throws {
        let items = XRPCTestClient.makeParameters(params: ["param1[]": ["1", "2", "3"], "param2": "hello", ";,/?:@&=+$#-_.!~*'()[]": ";,/?:@&=+$#-_.!~*'()[]"])
        XCTAssertEqual(items.map(\.description).sorted(), [#"%3B%2C%2F%3F%3A%40%26%3D%2B%24%23-_.%21%7E%2A%27%28%29%5B%5D=%3B%2C%2F%3F%3A%40%26%3D%2B%24%23-_.%21%7E%2A%27%28%29%5B%5D"#, "param1%5B%5D=1", "param1%5B%5D=2", "param1%5B%5D=3", "param2=hello"])
    }

    func testLexLinkCodable() throws {
        let json = #"{"$link":"bafkreibxn7ww5xcnkgwii3cndu46ike6reqllouvapfevfrxscpm3ovveq"}"#
        let decoder = JSONDecoder()
        let link = try decoder.decode(LexLink.self, from: Data(json.utf8))
        let cid = try CID(version: .v1, codec: .raw, multihash: Multihash(raw: "cids(1)", hashedWith: .sha2_256))
        XCTAssertEqual(link.toBaseEncodedString, cid.toBaseEncodedString)
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = XRPCTestClient.dataEncodingStrategy
        XCTAssertEqual(try String(decoding: encoder.encode(link), as: UTF8.self), json)
    }

    func testLexBlobCodable() throws {
        let json = #"{"$type":"blob","mimeType":"image/jpeg","ref":{"$link":"bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy"},"size":1234}"#
        let decoder = JSONDecoder()
        let blob = try decoder.decode(LexBlob.self, from: Data(json.utf8))
        XCTAssertEqual(blob.ref.toBaseEncodedString, "bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dataEncodingStrategy = XRPCTestClient.dataEncodingStrategy
        XCTAssertEqual(try String(decoding: encoder.encode(blob), as: UTF8.self), json)
    }

    func testLexBlobCodableLegacyCase() throws {
        let json = #"{"$type":"blob","mimeType":"image/jpeg","ref":{"$link":"bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy"},"size":0}"#
        let legacyJson = #"{"cid": "bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy","mimeType": "image/jpeg"}"#
        let decoder = JSONDecoder()
        let blob = try decoder.decode(LexBlob.self, from: Data(legacyJson.utf8))
        XCTAssertEqual(blob.ref.toBaseEncodedString, "bafkreibme22gw2h7y2h7tg2fhqotaqjucnbc24deqo72b6mkl2egezxhvy")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dataEncodingStrategy = XRPCTestClient.dataEncodingStrategy
        XCTAssertEqual(try String(decoding: encoder.encode(blob), as: UTF8.self), json)
    }

    func testUnknownRecordCodable() throws {
        let json = #"""
        {
          "$type" : "app.bsky.actor.defs#skyfeedBuilderFeedsPref",
          "key1" : {
            "nest_key1" : 123
          },
          "key2" : [
            {
              "nest_key2" : "abc",
              "nest_key3" : true
            },
            {
              "nest_key2" : "xyz",
              "nest_key3" : false
            }
          ]
        }
        """#
        let decoder = JSONDecoder()
        let record = try decoder.decode(UnknownRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.type, "app.bsky.actor.defs#skyfeedBuilderFeedsPref")
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = XRPCTestClient.dataEncodingStrategy
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(try String(decoding: encoder.encode(record), as: UTF8.self), json)
    }
}
