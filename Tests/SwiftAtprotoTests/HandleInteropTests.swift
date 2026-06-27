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
}
