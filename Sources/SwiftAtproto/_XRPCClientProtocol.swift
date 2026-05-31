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

  @available(*, deprecated, renamed: "call", message: "Use the type-safe 'call(_:input:retry:)' method instead.")
  func fetch<T: Decodable>(
    endpoint: String, contentType: String, httpMethod: HTTPMethod, params: Parameters?,
    input: (some Encodable)?, retry: Bool
  ) async throws -> T
  func refreshSession() async -> Bool

  static var errorDomain: String { get }
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

extension _XRPCClientProtocol {
  public static var errorDomain: String { "XRPCErrorDomain" }
}

extension ATPClientProtocol {
  public func getProxy(nsid _: String) -> String? { nil }
  public static var errorDomain: String { "ATPErrorDomain" }

  private static func encode(_ string: String, component: XRPCComponent) -> String {
    switch component {
    case .nsid:
      string.addingPercentEncoding(withAllowedCharacters: .nsidAllowed) ?? string
    case .parameter:
      string.addingPercentEncoding(withAllowedCharacters: .parameterAllowed) ?? string
    }
  }

  @available(*, deprecated, renamed: "call", message: "Use the type-safe 'call(_:input:retry:)' method instead.")
  public func fetch<T: Decodable>(
    endpoint nsid: String, contentType: String, httpMethod: HTTPMethod, params: Parameters?, input: (some Encodable)?, retry: Bool
  ) async throws -> T {
    var url = serviceEndpoint.appending(path: Self.encode(nsid, component: .nsid))
    if httpMethod == .get, let params = params {
      url.append(percentEncodedQueryItems: Self.makeParameters(params: params))
    }

    var request = URLRequest(url: url)
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    if let authorization = getAuthorization(endpoint: nsid) {
      request.addValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
    }
    if let proxy = getProxy(nsid: nsid) {
      request.addValue(proxy, forHTTPHeaderField: "atproto-proxy")
    }
    switch httpMethod {
    case .get:
      request.httpMethod = "GET"
    case .post:
      request.httpMethod = "POST"
      request.addValue(contentType, forHTTPHeaderField: "Content-Type")
      if let input {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .xrpc
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let body: Data =
          switch input {
          case let data as Data:
            data
          default:
            try encoder.encode(input)
          }
        request.httpBody = body
        request.addValue("\(body.count)", forHTTPHeaderField: "Content-Length")
      }
    }

    let (data, statusCode) = try await URLSession.shared.executeTask(for: request)

    guard 200...299 ~= statusCode else {
      if let error = try? decoder.decode(UnExpectedError.self, from: data) {
        if tokenIsExpired(error: error), retry, await refreshSession() {
          return try await fetch(
            endpoint: Self.encode(nsid, component: .nsid), contentType: contentType, httpMethod: httpMethod,
            params: params, input: input, retry: false
          )
        }
        throw error
      } else {
        let message = String(decoding: data, as: UTF8.self)
        throw NSError(domain: Self.errorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Server error: \(message)(\(statusCode))"])
      }
    }

    if T.self == Bool.self {
      return true as! T
    }
    if T.self == Data.self {
      return data as! T
    }
    return try decoder.decode(T.self, from: data)
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
