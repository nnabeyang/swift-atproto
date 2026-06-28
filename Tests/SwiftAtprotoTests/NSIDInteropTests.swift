import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `nsid` string format.
struct NSIDInteropTests {
  static let validNSIDs: [String] = [
    // Typical lexicon NSIDs.
    "com.example.foo",
    "com.example.feed.post",
    "org.example.actor.profile",
    "net.example.repo.createRecord",
    // Authority segments may contain digits or start with a digit (but the first segment may
    // not start with a digit; subsequent ones can).
    "a.0.c",
    "org.4chan.lex.getThing",
    // Name segment is camelCase friendly (alpha + digit, no hyphen).
    "com.example.fooBar",
    "com.example.foo123",
    // Minimum 3 segments.
    "a.b.c",
    // Hyphen allowed in non-name segments.
    "co-op.example.foo",
    "com.example-org.foo",
  ]

  @Test(arguments: validNSIDs)
  func validParses(_ input: String) throws {
    let nsid = try NSID(string: input)
    #expect(nsid.rawValue == input)
  }

  static let invalidNSIDs: [String] = [
    // Empty / too few segments.
    "", "com", "com.example",
    // First segment must not start with a digit.
    "0two.example.foo",
    // Name must not start with a digit or contain a hyphen.
    "com.example.0foo", "com.example.foo-bar", "a-0.b-1.c-3",
    // Edge hyphen on any segment.
    "-com.example.foo", "com-.example.foo", "com.example.-foo",
    // Empty segment (consecutive dots, leading or trailing dot).
    "com..example.foo", ".com.example.foo", "com.example.foo.",
    // Disallowed characters.
    "com.example.foo_bar", "com.example.foo bar", "com.example.foo@bar",
    "com.example.foo!bar",
    // Whitespace / control.
    "com.example.foo\t", "com.example.foo\n", " com.example.foo",
    // Uppercase letters not allowed in name segment? bluesky-social allows both — name may be
    // camelCase. We *do* accept these, so they're not in this invalid list.
  ]

  @Test(arguments: invalidNSIDs)
  func invalidThrows(_ input: String) {
    #expect(throws: (any Error).self) { try NSID(string: input) }
  }

  @Test func acceptsExactly317ByteInput() throws {
    // 63 + 1 + 63 + 1 + 63 + 1 + 63 + 1 + 61 = 317 byte total (4 authority labels + name).
    let label63 = String(repeating: "a", count: 63)
    let label61 = String(repeating: "a", count: 61)
    let input = "\(label63).\(label63).\(label63).\(label63).\(label61)"
    let nsid = try NSID(string: input)
    #expect(nsid.rawValue.utf8.count == 317)
  }

  @Test func rejectsOver317ByteInput() {
    let label63 = String(repeating: "a", count: 63)
    let label62 = String(repeating: "a", count: 62)
    let input = "\(label63).\(label63).\(label63).\(label63).\(label62)"
    #expect(input.utf8.count == 318)
    #expect(throws: (any Error).self) { try NSID(string: input) }
  }

  @Test func rejectsLabelOverSixtyThreeBytes() {
    let label64 = String(repeating: "a", count: 64)
    let input = "\(label64).example.foo"
    #expect(throws: (any Error).self) { try NSID(string: input) }
  }

  // MARK: authority and name accessors

  @Test func authorityReversesAllSegmentsExceptName() throws {
    // com.example.foo → authority "example.com", name "foo".
    let nsid = try NSID(string: "com.example.foo")
    #expect(nsid.authority == "example.com")
    #expect(nsid.name == "foo")
  }

  @Test func authorityHandlesFourLabelAuthority() throws {
    // org.4chan.lex.getThing → authority "lex.4chan.org", name "getThing".
    let nsid = try NSID(string: "org.4chan.lex.getThing")
    #expect(nsid.authority == "lex.4chan.org")
    #expect(nsid.name == "getThing")
  }

  @Test func authorityForMinimumThreeSegments() throws {
    // a.b.c → authority "b.a", name "c".
    let nsid = try NSID(string: "a.b.c")
    #expect(nsid.authority == "b.a")
    #expect(nsid.name == "c")
  }

  @Test func authorityForTypicalLexiconName() throws {
    let nsid = try NSID(string: "com.example.feed.post")
    #expect(nsid.authority == "feed.example.com")
    #expect(nsid.name == "post")
  }

  @Test func namePreservesCamelCase() throws {
    let nsid = try NSID(string: "com.example.fooBar")
    #expect(nsid.name == "fooBar")
  }
}
