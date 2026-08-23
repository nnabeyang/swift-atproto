import Foundation

/// A Lexicon string field that keeps its wire value and parses on demand.
///
/// Decodes and encodes as a plain `String`, so a value this library would
/// reject still round-trips byte-for-byte and a record signed elsewhere keeps
/// its signature valid. See <doc:LexiconStringFormats>.
///
/// Equality and hashing use ``rawValue`` (the wire string), not the parsed
/// value; compare ``typed`` to compare by value.
public struct FormatString<T: LexiconStringFormat>: RawRepresentable, Codable, Hashable, Sendable {
  /// The wire string, exactly as it was decoded.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Stores the canonical `typed.rawValue`, which may differ from a decoded wire string.
  public init(_ typed: T) {
    rawValue = typed.rawValue
  }

  /// The value parsed strictly, or `nil` when ``rawValue`` does not satisfy the
  /// format.
  public var typed: T? { try? T(string: rawValue) }

  /// The value parsed with the format's relaxed rules, or `nil` when it does
  /// not parse at all.
  ///
  /// Identical to ``typed`` for formats that define no relaxed reading.
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
