import Foundation

public protocol ATPClientProtocol: _XRPCCallable {
  var serviceEndpoint: URL { get }
  var decoder: JSONDecoder { get }

  func tokenIsExpired(error: some XRPCError) -> Bool
  func getAuthorization(endpoint: String) -> String?

  func refreshSession() async -> Bool
}

public protocol _XRPCClientProtocol: ATPClientProtocol {
  var auth: any XRPCAuth { get set }

  func signout()
}

extension ATPClientProtocol {
  public func getProxy(nsid _: String) -> String? { nil }
}

public protocol XRPCError: Error, LocalizedError, Decodable, Sendable {
  var error: String? { get }
  var message: String? { get }
  init(error: UnExpectedError)
}

extension XRPCError {
  public var errorDescription: String? {
    message
  }
}

public final class UnExpectedError: XRPCError {
  public let error: String?
  public let message: String?
  public init(error: String?, message: String?) {
    self.error = error
    self.message = message
  }

  public init(error: UnExpectedError) {
    self.error = error.error
    self.message = error.message
  }
}

public struct UnknownRecord: Identifiable, ATProtoRecord {
  public static let nsId = "unknown"
  public let type: String
  public var _unknownValues: [String: AnyCodable]

  enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public var id: String { UUID().uuidString }

  public init(type: String) {
    self.type = type
    _unknownValues = [:]
  }

  public init(from decoder: any Decoder) throws {
    let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
    type = try keyedContainer.decode(String.self, forKey: .type)
    let unknownContainer = try decoder.container(keyedBy: AnyCodingKeys.self)
    var _unknownValues = [String: AnyCodable]()
    for key in unknownContainer.allKeys {
      guard CodingKeys(rawValue: key.stringValue) == nil else {
        continue
      }
      _unknownValues[key.stringValue] = try unknownContainer.decode(AnyCodable.self, forKey: key)
    }
    self._unknownValues = _unknownValues
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try _unknownValues.encode(to: encoder)
  }
}

enum XRPCComponent {
  case nsid
  case parameter
}
