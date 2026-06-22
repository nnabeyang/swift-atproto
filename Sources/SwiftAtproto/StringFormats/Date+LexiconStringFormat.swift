import Foundation

extension Date: LexiconStringFormat {
  public init(string: String) throws {
    self = try Date(string, strategy: .atprotoDatetime)
  }

  // Canonical UTC, millisecond precision; lossy for sub-millisecond instants and zone offsets.
  public var rawValue: String {
    ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }
}
