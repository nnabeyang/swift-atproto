import Foundation
import Testing

@testable import SwiftAtproto

struct DatetimeKnownLimitationsTests {
  // Sub-millisecond rounding at year 9999 must not overflow into a 5-digit year.
  // A non-parsed Date at 9999-12-31T23:59:59.9996Z rounds up in rawValue past the 4-digit-year
  // boundary; the format layer clamps it back to the last representable millisecond.
  @Test func nonParseMaxYearDoesNotOverflow() throws {
    let date = Date(timeIntervalSince1970: 253_402_300_799.9996)
    #expect(date.rawValue == "9999-12-31T23:59:59.999Z")
    #expect(throws: Never.self) { try Date(string: date.rawValue) }
  }

  // The same logical instant must canonicalise identically whether it reaches rawValue
  // through the parser or through Date(timeIntervalSince1970:).
  @Test func parseAndRawValueAgreeOnSubMillisecond() throws {
    let parsed = try Date(string: "2024-01-15T12:30:00.0007Z").rawValue
    let constructed = Date(timeIntervalSince1970: 1_705_321_800.0007).rawValue
    #expect(parsed == constructed)
    #expect(parsed == "2024-01-15T12:30:00.001Z")
  }

  // Regression guard against a naive floor(t*1000) reduction. Double("X.999") is stored as
  // ~X.998999...; only (t*1000).rounded() recovers the millisecond exactly. This test fails
  // immediately if someone rewrites the format path to truncate.
  @Test func rawValueForExactMillisecondNineNineNine() throws {
    let date = Date(timeIntervalSince1970: 1_705_321_800.999)
    #expect(date.rawValue == "2024-01-15T12:30:00.999Z")
  }
}
