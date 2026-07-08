import Foundation

// Canonical AT Protocol datetime: UTC, millisecond precision; lossy for sub-millisecond instants and
// zone offsets. Formatted in the proleptic Gregorian calendar (consistent with parsing) rather than
// via `ISO8601Format`, which applies the Julian cutover before 1582.
public struct AtprotoDatetimeFormatStyle: FormatStyle {
  public init() {}

  private static let calendar = ProlepticGregorianCalendar()

  public func format(_ value: Date) -> String {
    let millis = Int((value.timeIntervalSince1970 * 1000).rounded())
    var days = millis / 86_400_000
    var msOfDay = millis % 86_400_000
    if msOfDay < 0 {
      days -= 1
      msOfDay += 86_400_000
    }
    let secondOfDay = msOfDay / 1000
    let c = Self.calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSince1970: Double(days) * 86_400 + Double(secondOfDay)))
    // Sub-millisecond rounding at year 9999 can push year to 10000; a 4-digit-year format
    // cannot represent that, so clamp to the last representable millisecond.
    if c.year! > 9999 {
      return "9999-12-31T23:59:59.999Z"
    }
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
      c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, msOfDay % 1000)
  }
}

extension FormatStyle where Self == AtprotoDatetimeFormatStyle {
  public static var atprotoDatetime: Self { .init() }
}
