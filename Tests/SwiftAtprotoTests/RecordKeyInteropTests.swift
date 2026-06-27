import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `record-key` string format.
struct RecordKeyInteropTests {
  static let validRecordKeys: [String] = [
    // Common forms.
    "3jzfcijpj2z2a",
    "self",
    "abc",
    "a",
    // Allowed punctuation (`_~.:-`).
    "abc-def",
    "abc_def",
    "abc.def",
    "abc:def",
    "abc~def",
    // Mixed case and digits.
    "ABC123",
    "a1b2c3",
    // Multiple dots are allowed as long as the whole string is not exactly `.` or `..`.
    "...",
    "....foo",
    "foo.bar.baz",
  ]

  @Test(arguments: validRecordKeys)
  func validParses(_ input: String) throws {
    let key = try RecordKey(string: input)
    #expect(key.rawValue == input)
  }

  static let invalidRecordKeys: [String] = [
    // Empty.
    "",
    // Special forbidden values.
    ".", "..",
    // Disallowed characters (anything outside alnum + `_~.:-`).
    "abc def", "abc/def", "abc@def", "abc#def", "abc(def", "abc%def", "abc+def", "abc=def",
    "abc,def", "abc;def", "abc?def", "abc!def", "abc*def", "abc<def", "abc>def", "abc[def",
    "abc'def", "abc\"def", "abc\\def",
    // Whitespace / control characters.
    "abc\u{0001}", "abc\t", "abc\n", " abc",
  ]

  @Test(arguments: invalidRecordKeys)
  func invalidThrows(_ input: String) {
    #expect(throws: (any Error).self) { try RecordKey(string: input) }
  }

  @Test func acceptsExactly512ByteInput() throws {
    let input = String(repeating: "a", count: 512)
    let key = try RecordKey(string: input)
    #expect(key.rawValue.utf8.count == 512)
  }

  @Test func rejectsOver512ByteInput() {
    let input = String(repeating: "a", count: 513)
    #expect(throws: (any Error).self) { try RecordKey(string: input) }
  }
}
