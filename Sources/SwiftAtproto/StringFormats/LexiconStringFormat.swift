import Foundation

/// A Lexicon `string` format such as `did`, `handle`, `at-uri`, or `datetime`.
///
/// Conforming types validate the wire shape of a string and expose it as
/// ``rawValue``. Generated models do not store them directly; they store
/// ``FormatString``, which keeps the wire string and parses on demand. See
/// <doc:LexiconStringFormats>.
public protocol LexiconStringFormat: Hashable, Sendable {
  /// The canonical wire string for this value.
  var rawValue: String { get }
  /// Parses `string` strictly, throwing ``LexiconStringFormatError`` when it
  /// does not satisfy the format.
  init(string: String) throws
  /// Parses `string`, optionally with the format's relaxed rules.
  ///
  /// Formats with no relaxed reading ignore `strict` and always parse strictly.
  init(string: String, strict: Bool) throws
}

extension LexiconStringFormat {
  /// Formats without a lenient override (most identifier formats) fall through to strict.
  public init(string: String, strict: Bool) throws {
    try self.init(string: string)
  }
}

/// A failure to parse a Lexicon string format.
public enum LexiconStringFormatError: Error, Equatable {
  /// The value does not satisfy the named format's grammar.
  case invalid(format: String, value: String)
  /// The value is longer than the named format's byte limit.
  case tooLong(format: String, limit: Int)
}
