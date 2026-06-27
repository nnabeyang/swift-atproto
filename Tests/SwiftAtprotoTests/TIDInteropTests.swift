import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `tid` string format. Always 13 base32-sortable chars; the
// leading char is restricted to `[234567abcdefghij]`.
struct TIDInteropTests {
  static let validTIDs: [String] = [
    // Realistic-looking TIDs.
    "3jzfcijpj2z2a",
    "3kbgyjzqfeq2e",
    // Boundary first characters (lowest = '2', highest of the restricted set = 'j').
    "2222222222222",
    "jzzzzzzzzzzzz",
    // All-digit boundaries within the alphabet (no 0, 1, 8, 9).
    "7zzzzzzzzzzzz",
    "234567abcdefg",
    // Representative letter-start TID (boundary first chars 2, 7, j are covered above).
    "abcdefghijklm",
  ]

  @Test(arguments: validTIDs)
  func validParses(_ input: String) throws {
    let tid = try TID(string: input)
    #expect(tid.rawValue == input)
  }

  static let invalidTIDs: [String] = [
    // Empty / wrong length.
    "",
    "234567abcdef",  // 12
    "234567abcdefgh",  // 14
    // First char outside [234567abcdefghij].
    "1234567abcdef",  // first '1'
    "0234567abcdef",  // first '0'
    "82345abcdefgh",  // first '8'
    "92345abcdefgh",  // first '9'
    "k234567abcdef",  // first 'k' (>= position 14 of the alphabet)
    "z234567abcdef",  // first 'z'
    "A234567abcdef",  // uppercase
    // Disallowed char in subsequent positions (`0`, `1`, `8`, `9` not in base32-sortable).
    "3jzfcijpj0z2a", "3jzfcijpj1z2a", "3jzfcijpj8z2a", "3jzfcijpj9z2a",
    // Uppercase in the body.
    "3jzfcijpj2z2A",
    // Disallowed punctuation.
    "3jzfcijpj-z2a", "3jzfcijpj.z2a", "3jzfcijpj_z2a",
    // Whitespace / control.
    "3jzfcijpj z2a", "3jzfcijpj\tz2a", "3jzfcijpj\nz2a",
  ]

  @Test(arguments: invalidTIDs)
  func invalidThrows(_ input: String) {
    #expect(throws: (any Error).self) { try TID(string: input) }
  }
}
