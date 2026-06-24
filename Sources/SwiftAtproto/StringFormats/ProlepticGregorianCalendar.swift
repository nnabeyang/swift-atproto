import Foundation

// A minimal, UTC-fixed proleptic Gregorian calendar for AT Protocol `datetime`. Foundation's
// `Calendar`/`NSCalendar` and the modern `Date.FormatStyle`/`ParseStrategy` all apply the 1582-10-15
// Julian cutover with no public proleptic control; only the legacy `DateFormatter.gregorianStartDate`
// is proleptic, but it can't express atproto's datetime grammar. Julian-day math: Richards'
// algorithm, Gregorian branch.
struct ProlepticGregorianCalendar {
  // Julian Day Number of 1970-01-01.
  private static let julianDayAtUnixEpoch = 2_440_588

  // Unlike `Calendar`, this is strict: a non-existent date (month 13, 2024-02-30, …) returns nil
  // rather than being normalized. Components are interpreted in UTC.
  func date(from components: DateComponents) -> Date? {
    guard let year = components.year, let month = components.month, let day = components.day,
      (1...12).contains(month), (1...Self.daysInMonth(year: year, month: month)).contains(day)
    else { return nil }
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    let second = components.second ?? 0
    let days = Self.julianDay(year: year, month: month, day: day) - Self.julianDayAtUnixEpoch
    let seconds = Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second)
    return Date(timeIntervalSince1970: seconds)
  }

  // Components are returned in UTC; only the fields this package uses are produced.
  func dateComponents(_ components: Set<Calendar.Component>, from date: Date) -> DateComponents {
    let total = Int(date.timeIntervalSince1970.rounded(.down))
    let days = Self.floorDivide(total, 86_400)
    let secondOfDay = total - days * 86_400
    let (year, month, day) = Self.yearMonthDay(fromJulianDay: days + Self.julianDayAtUnixEpoch)
    var result = DateComponents()
    if components.contains(.year) { result.year = year }
    if components.contains(.month) { result.month = month }
    if components.contains(.day) { result.day = day }
    if components.contains(.hour) { result.hour = secondOfDay / 3600 }
    if components.contains(.minute) { result.minute = secondOfDay % 3600 / 60 }
    if components.contains(.second) { result.second = secondOfDay % 60 }
    return result
  }

  // MARK: - Proleptic Gregorian helpers

  private static func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12: 31
    case 4, 6, 9, 11: 30
    case 2: isLeapYear(year) ? 29 : 28
    default: 0
    }
  }

  private static func floorDivide(_ a: Int, _ b: Int) -> Int {
    a >= 0 ? a / b : -((-a + b - 1) / b)
  }

  private static func modulo(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r >= 0 ? r : r + b
  }

  static func julianDay(year: Int, month: Int, day: Int) -> Int {
    let y = 4716
    let j = 1401
    let m = 2
    let n = 12
    let r = 4
    let p = 1461
    let q = 0
    let u = 5
    let s = 153
    let t = 2
    let a = 184
    let c = -38
    let h = month - m
    let g = (year + y) - (n - h) / n
    let f = (h - 1 + n) % n
    let e = (p * g + q) / r + day - 1 - j
    let bigJ = e + (s * f + t) / u
    return bigJ - (3 * ((g + a) / 100)) / 4 - c
  }

  static func yearMonthDay(fromJulianDay julianDay: Int) -> (year: Int, month: Int, day: Int) {
    let y = 4716
    let j = 1401
    let m = 2
    let n = 12
    let r = 4
    let p = 1461
    let v = 3
    let u = 5
    let s = 153
    let w = 2
    let b = 274_277
    let c = -38
    let f = julianDay + j + (((4 * julianDay + b) / 146_097) * 3) / 4 + c
    let e = r * f + v
    let g = modulo(e, p) / r
    let h = u * g + w
    let day = floorDivide(h % s, u) + 1
    let month = (floorDivide(h, s) + m) % n + 1
    let year = floorDivide(e, p) - y + (n + m - month) / n
    return (year, month, day)
  }
}
