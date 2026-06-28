import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum HTTPMethod {
  case get
  case post
}

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

extension URLSession {
  func executeTask(for request: URLRequest) async throws -> (Data, UInt) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      fatalError()
    }
    return (data, UInt(httpResponse.statusCode))
  }
}

extension ATPClientProtocol {
  public func getProxy(nsid _: String) -> String? { nil }

  private static func encode(_ string: String, component: XRPCComponent) -> String {
    switch component {
    case .nsid:
      string.addingPercentEncoding(withAllowedCharacters: .nsidAllowed) ?? string
    case .parameter:
      string.addingPercentEncoding(withAllowedCharacters: .parameterAllowed) ?? string
    }
  }

  public func call<X: XRPCQuery>(_ requestType: X.Type, input: X.Input.Query, retry _: Bool) async throws -> X.ResponseBody {
    try await call(requestType, input: input)
  }

  public func call<X: XRPCProcedure>(_ requestType: X.Type, input: X.RequestBody? = nil, retry _: Bool) async throws -> X.ResponseBody {
    try await call(requestType, input: input)
  }
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
