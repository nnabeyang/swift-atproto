import Foundation
import Testing

@testable import SwiftAtproto

struct DatetimeFormatTests {
  @Test(arguments: [
    "2024-01-15T12:30:00Z",
    "2024-01-15T12:30:00+09:00",
    "1985-04-12T23:20:50.123Z",
    "1985-04-12T23:20:50.1Z",
    "1985-04-12T23:20:50.123456Z",
    "1985-04-12T23:20:50.123456789012Z",
    "1985-04-12T23:20:50Z",
    "1985-04-12T23:20:50.123+01:45",
    "0001-01-01T00:00:00.000Z",
    "0123-01-01T00:00:00.000Z",
    "0000-01-01T00:00:00.000Z",
    "3001-12-31T23:00:00.000Z",
  ])
  func validDatetimesParse(_ value: String) throws {
    _ = try Date(string: value)
  }

  @Test(arguments: [
    "",
    "2024-01-15",
    "2024-01-15T12:30:00",
    "2024-13-01T00:00:00Z",
    "2024-01-15T12:30:00-00:00",
    "2024-01-15T12:30:00z",
  ])
  func invalidDatetimesThrow(_ value: String) {
    #expect(throws: (any Error).self) { try Date(string: value) }
  }

  @Test func negativeTimeThrows() {
    #expect(throws: (any Error).self) { try Date(string: "0000-01-01T00:00:00+01:00") }
  }

  @Test func tooLongThrowsTooLong() {
    let value = "2024-01-15T12:30:00.\(String(repeating: "0", count: 64))Z"
    #expect(throws: LexiconStringFormatError.tooLong(format: "datetime", limit: 64)) {
      try Date(string: value)
    }
  }

  @Test func rawValueIsCanonicalMillisecondUTC() throws {
    let date = try Date(string: "2024-01-15T12:30:00Z")
    #expect(date.rawValue == "2024-01-15T12:30:00.000Z")
    #expect(try Date(string: date.rawValue) == date)
  }

  @Test func rawValueRoundTripPreservesInstant() throws {
    let date = try Date(string: "2024-01-15T12:30:00+09:00")
    #expect(try Date(string: date.rawValue) == date)
  }

  @Test func parseStrategyDirectUsage() throws {
    _ = try Date("2024-01-15T12:30:00.123456Z", strategy: .atprotoDatetime)
    #expect(throws: (any Error).self) { try Date("not-a-datetime", strategy: .atprotoDatetime) }
  }

  @Test(arguments: [
    "2024-01-15T12:30:00+19:00",
    "2024-01-15T12:30:00+23:00",
    "2024-01-15T12:30:00+23:59",
    "2024-01-15T12:30:00-23:00",
  ])
  func largeOffsetsBeyond18HoursParse(_ value: String) throws {
    _ = try Date(string: value)
  }

  @Test func largeOffsetComputesCorrectInstant() throws {
    let withOffset = try Date(string: "2024-01-02T00:00:00+23:00")
    let utc = try Date(string: "2024-01-01T01:00:00Z")
    #expect(withOffset == utc)
  }

  @Test(arguments: [
    "1985-04-12T23:59:60Z",
    "2024-01-15T12:30:60Z",
    "2024-01-15T12:30:60.000Z",
  ])
  func leapSecondIsRejected(_ value: String) {
    #expect(throws: (any Error).self) { try Date(string: value) }
  }

  @Test func fractionDigitLimit() throws {
    _ = try Date(string: "1985-04-12T23:20:50.12345678901234567890Z")  // 20
    #expect(throws: (any Error).self) {
      try Date(string: "1985-04-12T23:20:50.123456789012345678901Z")  // 21
    }
  }

  @Test func rawValueCanonicalizesSubMillisecond() throws {
    let date = try Date(string: "2024-01-15T12:30:00.123456Z")
    #expect(date.rawValue == "2024-01-15T12:30:00.123Z")
  }

  @Test(arguments: [
    ("2024-01-15T12:30:00+19:00", "2024-01-14T17:30:00Z"),
    ("2024-01-15T12:30:00-23:00", "2024-01-16T11:30:00Z"),
    ("2024-01-15T12:30:00+01:45", "2024-01-15T10:45:00Z"),
  ])
  func largeOffsetsComputeCorrectInstant(_ offset: String, _ utc: String) throws {
    #expect(try Date(string: offset) == Date(string: utc))
  }

  @Test func prolepticGregorianCalendar() throws {
    // 1500 is a leap year in the Julian calendar but not in the proleptic Gregorian one.
    #expect(throws: (any Error).self) { try Date(string: "1500-02-29T00:00:00Z") }
    // 1582-10-10 does not exist in the Julian/Gregorian cutover but is valid proleptically.
    _ = try Date(string: "1582-10-10T00:00:00Z")
    #expect(try Date(string: "2024-02-29T00:00:00Z").timeIntervalSince1970 == 1_709_164_800)
  }

  @Test func pre1582InstantsMatchProlepticGregorian() throws {
    #expect(try Date(string: "1000-12-31T23:00:00.000Z").timeIntervalSince1970 == -30_578_691_600)
    #expect(try Date(string: "0000-01-01T00:00:00.000Z").timeIntervalSince1970 == -62_167_219_200)
  }

  @Test(arguments: [
    "1000-12-31T23:00:00.000Z",
    "0985-04-12T23:20:50.123Z",
    "1582-10-10T00:00:00.000Z",
    "0000-01-01T00:00:00.000Z",
  ])
  func rawValueIsProlepticForPre1582Dates(_ value: String) throws {
    // rawValue must round-trip the wire date even before the Julian/Gregorian cutover.
    #expect(try Date(string: value).rawValue == value)
  }

  @Test(arguments: [
    // Divisible by 400 are leap; divisible by 100 but not 400 are not.
    ("1600-02-29T00:00:00Z", true),
    ("2000-02-29T00:00:00Z", true),
    ("1700-02-29T00:00:00Z", false),
    ("1900-02-29T00:00:00Z", false),
  ])
  func centuryLeapYears(_ value: String, _ valid: Bool) {
    if valid {
      #expect(throws: Never.self) { try Date(string: value) }
    } else {
      #expect(throws: (any Error).self) { try Date(string: value) }
    }
  }

  @Test(arguments: [
    "2024-01-15T12:30:00+24:00",
    "2024-01-15T12:30:00+23:60",
    "2024-01-15T12:30:00-24:00",
  ])
  func outOfRangeOffsetsThrow(_ value: String) {
    #expect(throws: (any Error).self) { try Date(string: value) }
  }

  @Test func subMillisecondTruncates() throws {
    // Sub-millisecond digits are dropped (ms-precise, like the reference), not rounded up.
    #expect(try Date(string: "2024-01-15T12:30:00.1234Z").rawValue == "2024-01-15T12:30:00.123Z")
    #expect(try Date(string: "2024-01-15T12:30:00.1236Z").rawValue == "2024-01-15T12:30:00.123Z")
  }

  @Test func maxYearSubMillisecondDoesNotOverflow() throws {
    // Sub-millisecond truncation keeps the canonical value within year 9999 and re-parsable.
    let date = try Date(string: "9999-12-31T23:59:59.9999Z")
    #expect(date.rawValue == "9999-12-31T23:59:59.999Z")
    #expect(throws: Never.self) { try Date(string: date.rawValue) }
  }

  @Test func boundarySubMillisecondDoesNotCarry() throws {
    // .9999 must not roll over into the next day/month/year.
    #expect(try Date(string: "2024-12-31T23:59:59.9999Z").rawValue == "2024-12-31T23:59:59.999Z")
  }
}
