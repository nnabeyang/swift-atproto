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

  // MARK: timestamp / clockId accessors

  @Test func timestampAndClockIdRoundTripThroughBase32() throws {
    let knownTimestamp: UInt64 = 1_700_000_000_000_000  // µs since epoch
    let knownClockId: UInt16 = 42
    let value = (knownTimestamp << 10) | UInt64(knownClockId)
    let tid = try TID(string: encodeBase32Sortable(value: value))
    #expect(tid.timestamp == knownTimestamp)
    #expect(tid.clockId == knownClockId)
  }

  @Test func clockIdAtUpperTenBitBoundary() throws {
    // Per spec, clockId is 10 bits; 1023 is the maximum.
    let value = (UInt64(1_700_000_000_000_000) << 10) | UInt64(1023)
    let tid = try TID(string: encodeBase32Sortable(value: value))
    #expect(tid.clockId == 1023)
  }

  @Test func clockIdZero() throws {
    let value = UInt64(1_700_000_000_000_000) << 10  // clockId = 0
    let tid = try TID(string: encodeBase32Sortable(value: value))
    #expect(tid.clockId == 0)
  }

  @Test func allZeroTIDIsRecognized() throws {
    // The TID spec defines "2222222222222" as the zero value.
    let tid = try TID(string: "2222222222222")
    #expect(tid.timestamp == 0)
    #expect(tid.clockId == 0)
  }
}
