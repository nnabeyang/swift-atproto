import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `handle` string format.
struct HandleInteropTests {
  static let validHandles: [String] = [
    // Typical user handle form.
    "john.example.com",
    "jay.example.org",
    "alice.test",
    // Two-label minimum.
    "a.co",
    "example.com",
    // Punycode label (xn-- prefix) passes the same byte test.
    "xn--ls8h.test",
    // Intra-label hyphen is allowed (no edge hyphen).
    "with-hyphen.example.com",
    // Label may start with a digit; only the TLD is required to start with a letter.
    "1abc.example.com",
    "abc123.example.com",
    "9abc.example.com",
    // Many labels.
    "a.b.c.d.example.com",
    // Mixed case is preserved verbatim.
    "Alice.Example.Com",
  ]

  @Test(arguments: validHandles)
  func validParses(_ input: String) throws {
    let handle = try Handle(string: input)
    #expect(handle.rawValue == input)
  }

  static let invalidHandles: [String] = [
    // Empty / single label.
    "", "example", "john",
    // Dotless / leading dot / trailing dot / empty intermediate label.
    "a", ".example.com", "example.com.", "a..b",
    // TLD must start with a letter.
    "a.0", "a.b.0xy",
    // Label edge hyphen.
    "-foo.example.com", "foo-.example.com",
    // Disallowed characters in labels.
    "a@b.example.com", "a_b.example.com", "alice.example.com_test", "alice test.example.com",
    "alice..example.com",
    // Whitespace and control characters.
    "alice.example.com ", " alice.example.com", "alice.example.com\t", "alice.example.com\n",
  ]

  @Test(arguments: invalidHandles)
  func invalidThrows(_ input: String) {
    #expect(throws: (any Error).self) { try Handle(string: input) }
  }

  @Test func acceptsLabelAtSixtyThreeByteBoundary() throws {
    // Each label may be up to 63 byte. Build a 63 + 1 + 63 = 127-byte handle.
    let label = String(repeating: "a", count: 63)
    let input = "\(label).\(label)"
    let handle = try Handle(string: input)
    #expect(handle.rawValue.utf8.count == 127)
  }

  @Test func rejectsLabelOverSixtyThreeBytes() {
    let label = String(repeating: "a", count: 64)
    let input = "\(label).example.com"
    #expect(throws: (any Error).self) { try Handle(string: input) }
  }

  @Test func acceptsExactly253ByteInput() throws {
    // 63 + 1 + 63 + 1 + 63 + 1 + 61 = 253 byte. TLD `aaa…` starts with a letter.
    let label63 = String(repeating: "a", count: 63)
    let label61 = String(repeating: "a", count: 61)
    let input = "\(label63).\(label63).\(label63).\(label61)"
    let handle = try Handle(string: input)
    #expect(handle.rawValue.utf8.count == 253)
  }

  @Test func rejectsOver253ByteInput() {
    let label63 = String(repeating: "a", count: 63)
    let label62 = String(repeating: "a", count: 62)
    let input = "\(label63).\(label63).\(label63).\(label62)"
    #expect(input.utf8.count == 254)
    #expect(throws: (any Error).self) { try Handle(string: input) }
  }
}
