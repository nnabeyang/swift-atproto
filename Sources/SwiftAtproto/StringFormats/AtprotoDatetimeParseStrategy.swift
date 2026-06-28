import Foundation

public struct AtprotoDatetimeParseStrategy: ParseStrategy {
  static let maxLength = 64

  public let lenient: Bool

  public init(lenient: Bool = false) {
    self.lenient = lenient
  }

  private static let calendar = ProlepticGregorianCalendar()
  // 0000-01-01T00:00:00Z; instants before this are rejected.
  private static let astroZeroDate = calendar.date(from: DateComponents(year: 0, month: 1, day: 1))!

  public func parse(_ value: String) throws -> Date {
    func invalid() -> LexiconStringFormatError { .invalid(format: "datetime", value: value) }

    guard value.utf8.count <= Self.maxLength else {
      throw LexiconStringFormatError.tooLong(format: "datetime", limit: Self.maxLength)
    }

    let input = lenient ? Self.normalizeForLenient(value) : value
    var scanner = Scanner(input)
    guard let fields = scanner.scan() else { throw invalid() }

    // Resolve the instant in the proleptic Gregorian calendar (matching the reference
    // implementation). Foundation's calendars apply the 1582 Julian cutover, so a custom calendar is
    // used; `date(from:)` rejects non-existent dates such as 2024-02-30.
    guard
      let base = Self.calendar.date(
        from: DateComponents(
          year: fields.year, month: fields.month, day: fields.day,
          hour: fields.hour, minute: fields.minute, second: fields.second))
    else { throw invalid() }
    let instant = base.addingTimeInterval(-Double(fields.offsetSeconds) + (fields.fraction ?? 0))
    guard instant >= Self.astroZeroDate else { throw invalid() }

    return instant
  }
}

extension ParseStrategy where Self == AtprotoDatetimeParseStrategy {
  public static var atprotoDatetime: Self { .init() }
  public static var atprotoDatetimeLenient: Self { .init(lenient: true) }
}

extension AtprotoDatetimeParseStrategy {
  // Lenient pre-normalization: append `Z` when the input has no timezone designator (ends in a
  // digit). Other lenient normalizations stay opt-in for the caller.
  fileprivate static func normalizeForLenient(_ value: String) -> String {
    guard let last = value.last else { return value }
    if last == "Z" || last == "z" || last == "+" || last == "-" { return value }
    if let scalar = last.unicodeScalars.first, ("0"..."9").contains(Character(scalar)) {
      return value + "Z"
    }
    return value
  }
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
      // Truncate to millisecond precision (the reference implementation is millisecond-precise);
      // keeping sub-millisecond digits would let rounding in `Date.rawValue` overflow the year.
      var millis = 0
      for offset in 0..<3 {
        let i = start + offset
        millis = millis * 10 + (i < index ? Int(bytes[i] - UInt8(ascii: "0")) : 0)
      }
      fraction = Double(millis) / 1000
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
