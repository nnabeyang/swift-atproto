import Foundation

public struct AtprotoDatetimeParseStrategy: ParseStrategy {
  static let maxLength = 64

  public init() {}

  public func parse(_ value: String) throws -> Date {
    func invalid() -> LexiconStringFormatError { .invalid(format: "datetime", value: value) }

    guard value.utf8.count <= Self.maxLength else {
      throw LexiconStringFormatError.tooLong(format: "datetime", limit: Self.maxLength)
    }

    var scanner = Scanner(value)
    guard let fields = scanner.scan() else { throw invalid() }

    // Apply the offset arithmetically so offsets beyond ±18:00 (rejected by `TimeZone`) still parse.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = Self.components(
      year: fields.year, month: fields.month, day: fields.day, hour: fields.hour,
      minute: fields.minute, second: fields.second)
    guard let wallClock = calendar.date(from: components) else { throw invalid() }

    let check = calendar.dateComponents(
      [.era, .year, .month, .day, .hour, .minute, .second], from: wallClock)
    guard Self.astronomicalYear(era: check.era, year: check.year) == fields.year,
      check.month == fields.month, check.day == fields.day, check.hour == fields.hour,
      check.minute == fields.minute, check.second == fields.second
    else { throw invalid() }

    let instant = wallClock.addingTimeInterval(-Double(fields.offsetSeconds))

    let utc = calendar.dateComponents([.era, .year], from: instant)
    guard Self.astronomicalYear(era: utc.era, year: utc.year) >= 0 else { throw invalid() }

    if let fraction = fields.fraction { return instant.addingTimeInterval(fraction) }
    return instant
  }

  private static func components(
    year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
  ) -> DateComponents {
    var components = DateComponents()
    if year >= 1 {
      components.era = 1
      components.year = year
    } else {
      components.era = 0
      components.year = 1
    }
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    components.timeZone = TimeZone(secondsFromGMT: 0)!
    return components
  }

  private static func astronomicalYear(era: Int?, year: Int?) -> Int {
    guard let year else { return Int.min }
    return era == 0 ? 1 - year : year
  }
}

extension ParseStrategy where Self == AtprotoDatetimeParseStrategy {
  public static var atprotoDatetime: Self { .init() }
}

private struct Scanner {
  struct Fields {
    var year, month, day, hour, minute, second: Int
    var fraction: Double?
    var offsetSeconds: Int
  }

  let bytes: [UInt8]
  var index = 0

  init(_ value: String) { bytes = Array(value.utf8) }

  private var isAtEnd: Bool { index >= bytes.count }

  private func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

  private mutating func expect(_ ascii: Unicode.Scalar) -> Bool {
    guard index < bytes.count, bytes[index] == UInt8(ascii: ascii) else { return false }
    index += 1
    return true
  }

  private mutating func fixedDigits(_ count: Int) -> Int? {
    guard index + count <= bytes.count else { return nil }
    var result = 0
    for offset in 0..<count {
      let byte = bytes[index + offset]
      guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
      result = result * 10 + Int(byte - UInt8(ascii: "0"))
    }
    index += count
    return result
  }

  mutating func scan() -> Fields? {
    guard let year = fixedDigits(4), expect("-"),
      let month = fixedDigits(2), (1...12).contains(month), expect("-"),
      let day = fixedDigits(2), (1...31).contains(day), expect("T"),
      let hour = fixedDigits(2), (0...23).contains(hour), expect(":"),
      let minute = fixedDigits(2), (0...59).contains(minute), expect(":"),
      let second = fixedDigits(2), (0...59).contains(second)
    else { return nil }

    var fraction: Double?
    if peek() == UInt8(ascii: ".") {
      index += 1
      let start = index
      while let byte = peek(), byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
        index += 1
      }
      // 1 to 20 fraction digits.
      guard index > start, index - start <= 20 else { return nil }
      fraction = Double("0." + String(decoding: bytes[start..<index], as: UTF8.self))
    }

    guard let offsetSeconds = scanOffset() else { return nil }
    guard isAtEnd else { return nil }

    return Fields(
      year: year, month: month, day: day, hour: hour, minute: minute, second: second,
      fraction: fraction, offsetSeconds: offsetSeconds)
  }

  private mutating func scanOffset() -> Int? {
    guard let sign = peek() else { return nil }
    if sign == UInt8(ascii: "Z") {
      index += 1
      return 0
    }
    guard sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") else { return nil }
    index += 1
    guard let hours = fixedDigits(2), (0...23).contains(hours), expect(":"),
      let minutes = fixedDigits(2), (0...59).contains(minutes)
    else { return nil }
    let magnitude = hours * 3600 + minutes * 60
    if sign == UInt8(ascii: "-") {
      if magnitude == 0 { return nil }
      return -magnitude
    }
    return magnitude
  }
}
