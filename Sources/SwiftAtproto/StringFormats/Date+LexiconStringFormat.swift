import Foundation

extension Date: LexiconStringFormat {
  public init(string: String) throws {
    self = try Date(string, strategy: .atprotoDatetime)
  }

  public var rawValue: String { formatted(.atprotoDatetime) }
}
