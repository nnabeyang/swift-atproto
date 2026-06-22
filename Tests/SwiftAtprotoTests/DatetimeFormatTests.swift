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
}
