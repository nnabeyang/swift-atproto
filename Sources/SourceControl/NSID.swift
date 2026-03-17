import Foundation

public struct NSID: Codable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self = .init(rawValue: value)
  }

  public init(from decoder: any Decoder) throws {
    self.rawValue = try String(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    try rawValue.encode(to: encoder)
  }

  public var authoritiy: String {
    let parts = rawValue.split(separator: ".")
    guard parts.count >= 2 else { return "" }
    return parts.dropLast().reversed().joined(separator: ".")
  }

  public var name: String {
    let parts = rawValue.split(separator: ".")
    return String(parts[parts.count - 1])
  }

  public func url(from baseURL: URL) -> URL {
    baseURL.appending(component: rawValue.replacingOccurrences(of: ".", with: "/") + ".json")
  }
}
