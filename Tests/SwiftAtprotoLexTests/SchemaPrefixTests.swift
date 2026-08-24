import Foundation
import XCTest

@testable import SwiftAtprotoLex

final class SchemaPrefixTests: XCTestCase {
  func testDerivePrefixKeepsAuthorityForFourSegmentIds() {
    XCTAssertEqual(Schema.derivePrefix(from: "com.atproto.repo.strongRef"), "com.atproto")
    XCTAssertEqual(Schema.derivePrefix(from: "org.example.feed.like"), "org.example")
    XCTAssertEqual(Schema.derivePrefix(from: "com.example.repo.knots"), "com.example")
  }

  func testDerivePrefixDropsSingleSegmentForShortIds() {
    XCTAssertEqual(Schema.derivePrefix(from: "com.example.string"), "com.example")
    XCTAssertEqual(Schema.derivePrefix(from: "com.example"), "com")
  }

  func testDerivePrefixDropsTwoSegmentsForDeeperIds() {
    XCTAssertEqual(Schema.derivePrefix(from: "com.example.git.temp.getEntry"), "com.example.git")
  }

  func testDerivePrefixHandlesShortIds() {
    XCTAssertEqual(Schema.derivePrefix(from: "atproto"), "")
    XCTAssertEqual(Schema.derivePrefix(from: ""), "")
  }

  func testSchemaDecodeDerivesPrefixFromId() throws {
    let json = """
      {
        "lexicon": 1,
        "id": "com.atproto.repo.strongRef",
        "description": "A URI with a content-hash fingerprint.",
        "defs": {
          "main": {
            "type": "object",
            "required": ["uri", "cid"],
            "properties": {
              "uri": {"type": "string", "format": "at-uri"},
              "cid": {"type": "string", "format": "cid"}
            }
          }
        }
      }
      """.data(using: .utf8)!
    let schema = try JSONDecoder().decode(Schema.self, from: json)
    XCTAssertEqual(schema.id, "com.atproto.repo.strongRef")
    XCTAssertEqual(schema.prefix, "com.atproto")
    XCTAssertEqual(schema.defs["main"]?.prefix, "com.atproto")
    XCTAssertEqual(schema.defs["main"]?.id, "com.atproto.repo.strongRef")
  }
}
