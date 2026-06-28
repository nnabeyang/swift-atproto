import Foundation

extension Date: LexiconStringFormat {
  public init(string: String) throws {
    self = try Date(string, strategy: .atprotoDatetime)
  }

  public init(string: String, strict: Bool) throws {
    self = try Date(string, strategy: strict ? .atprotoDatetime : .atprotoDatetimeLenient)
  }

  public var rawValue: String { formatted(.atprotoDatetime) }
}
