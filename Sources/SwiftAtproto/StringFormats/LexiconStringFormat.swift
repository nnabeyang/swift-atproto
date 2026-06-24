import Foundation

public protocol LexiconStringFormat: Hashable, Sendable {
  var rawValue: String { get }
  init(string: String) throws
}

public enum LexiconStringFormatError: Error, Equatable {
  case invalid(format: String, value: String)
  case tooLong(format: String, limit: Int)
}
