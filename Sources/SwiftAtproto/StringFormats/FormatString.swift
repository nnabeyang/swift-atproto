import Foundation

// Equality and hashing use `rawValue` (the wire string), not the parsed value; compare `typed` to
// compare by value.
public struct FormatString<T: LexiconStringFormat>: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  // Stores the canonical `typed.rawValue`, which may differ from a decoded wire string.
  public init(_ typed: T) {
    rawValue = typed.rawValue
  }

  public var typed: T? { try? T(string: rawValue) }

  public var typedLenient: T? { try? T(string: rawValue, strict: false) }

  public init(from decoder: any Decoder) throws {
    rawValue = try String(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    try rawValue.encode(to: encoder)
  }
}

extension FormatString: CustomStringConvertible {
  public var description: String { rawValue }
}
