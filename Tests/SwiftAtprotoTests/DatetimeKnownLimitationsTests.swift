import Foundation

@testable import SwiftAtproto

// FIXME: Known limitations of `Date.rawValue` for non-parsed `Date` values (see below).
//
// These only affect a `Date` produced *outside* the parser (e.g. `Date()` or arithmetic) that is
// then wrapped with `FormatString(_:)` / read via `rawValue`. Values obtained from
// `Date(string:)` are unaffected: the parser truncates to millisecond precision, so neither issue
// can occur on the parse → rawValue round-trip.
//
// They are left unfixed because there is no FP-safe alternative: at year 9999 the instant is
// ~2.53e11 s, so `t * 1000` ≈ 2.53e14 is still an exact integer in a Double and `(t*1000).rounded()`
// recovers the millisecond exactly — but `(t*1_000_000)` ≈ 2.53e17 exceeds 2^53 and loses
// precision, and a plain `floor(t*1000)` underflows genuine millisecond values (e.g. 0.999 → 0.998).
// So `round` is the only FP-safe reduction, and `round` is precisely what causes F1/F2.
//
// The tests below reproduce the behaviour; uncomment to verify. They are expected to FAIL.
//
// F1 — sub-millisecond rounding overflows the year:
//   A non-parsed Date at 9999-12-31T23:59:59.9996Z rounds up in rawValue to the 5-digit year
//   "10000-01-01T00:00:00.000Z", which the scanner (4-digit year) cannot re-parse.
//
//   @Test func f1NonParseMaxYearOverflows() throws {
//     let date = Date(timeIntervalSince1970: 253402300799.9996)  // 9999-12-31T23:59:59.9996Z
//     #expect(date.rawValue == "9999-12-31T23:59:59.999Z")  // actual: "10000-01-01T00:00:00.000Z"
//     #expect(throws: Never.self) { try Date(string: date.rawValue) }  // actual: throws (5-digit year)
//   }
//
// F2 — sub-millisecond handling is asymmetric (parse truncates, rawValue rounds):
//   The same logical instant canonicalises differently depending on how the Date was produced.
//
//   @Test func f2ParseVsRawValueAsymmetry() throws {
//     let parsed = try Date(string: "2024-01-15T12:30:00.0007Z").rawValue       // truncates -> .000Z
//     let constructed = Date(timeIntervalSince1970: 1705321800.0007).rawValue   // rounds    -> .001Z
//     #expect(parsed == constructed)                                            // actual: .000Z != .001Z
//   }
