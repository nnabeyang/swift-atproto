import Foundation

public protocol LexiconStringFormat: Hashable, Sendable {
  var rawValue: String { get }
  init(string: String) throws
  init(string: String, strict: Bool) throws
}

extension LexiconStringFormat {
  // Formats without a lenient override (most identifier formats) fall through to strict.
  public init(string: String, strict: Bool) throws {
    try self.init(string: string)
  }
}

public enum LexiconStringFormatError: Error, Equatable {
  case invalid(format: String, value: String)
  case tooLong(format: String, limit: Int)
}
