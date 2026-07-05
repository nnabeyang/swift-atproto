import Foundation
import HTTPTypes

extension HTTPField.Name {
  static var atprotoProxy: Self { .init("atproto-proxy")! }
}

public protocol _XRPCCallable: Sendable {
  func getProxy(nsid: String) -> String?
  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data
  func call<X: XRPCQuery>(_ request: X.Type, input: X.Input.Query) async throws -> X.ResponseBody
  func call<X: XRPCProcedure>(_ request: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody
}

extension _XRPCCallable {
  public func call<X: XRPCQuery>(_ query: X.Type, input: X.Input.Query) async throws -> X.ResponseBody {
    let proxy = getProxy(nsid: X.id)
    try enforceScopeGuard(X.self, proxy: proxy)
    var request = try constructRequest(query, input: input)
    if let proxy {
      request.headers[.atprotoProxy] = proxy
    }
    return try await send(query, for: request)
  }

  public func call<X: XRPCProcedure>(_ procedure: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody {
    let proxy = getProxy(nsid: X.id)
    try enforceScopeGuard(X.self, proxy: proxy)
    var request = try constructRequest(procedure, input: input)
    if let proxy {
      request.headers[.atprotoProxy] = proxy
    }
    return try await send(procedure, for: request)
  }

  private func enforceScopeGuard<X: XRPCRequest>(_: X.Type, proxy: String?) throws {
    guard let session = (self as? ATPClientProtocol)?.oauthSession else { return }
    let lxm = X.requiredRpcLxm()
    let aud = proxy ?? "\(session.audienceDid.rawValue)#atproto_pds"
    guard session.grantedScopes.allowsRpc(lxm: lxm, aud: aud) else {
      throw OAuthScopeError.insufficientScope(lxm: lxm, aud: aud)
    }
  }

  private func send<X: XRPCRequest>(_: X.Type, for request: XRPCRequestComponents) async throws -> X.ResponseBody {
    do {
      let data = try await response(request)
      if X.ResponseBody.self == EmptyResponse.self {
        return EmptyResponse() as! X.ResponseBody
      }
      if X.ResponseBody.self == Data.self {
        return data as! X.ResponseBody
      }
      let decoder = JSONDecoder()
      return try decoder.decode(X.ResponseBody.self, from: data)
    } catch let error as UnExpectedError {
      throw X.Error(error: error)
    }
  }

  func constructRequest<X: XRPCQuery>(
    _ request: X.Type,
    input: X.Input.Query,
  ) throws -> XRPCRequestComponents {
    let queryItems = input.asParameters.map({ Self.makeParameters(params: $0) }) ?? .init()
    return .init(
      nsId: X.id,
      queryItems: queryItems,
      headers: .init(
        dictionaryLiteral: (.accept, "json/application")
      ),
      method: .get,
    )
  }

  func constructRequest<X: XRPCProcedure>(
    _ request: X.Type,
    input: X.RequestBody?,
  ) throws -> XRPCRequestComponents {
    var headerFields = HTTPFields()
    headerFields[.contentType] = X.contentType
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .xrpc
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let body: Data =
      switch input {
      case let data as Data:
        data
      case .none:
        Data()
      default:
        try encoder.encode(input)
      }

    return .init(
      nsId: X.id,
      queryItems: .init(),
      headers: headerFields,
      method: .post,
      body: body
    )
  }

  public static func makeParameters(params: Parameters) -> [URLQueryItem] {
    var items = [URLQueryItem]()
    for (key, value) in params {
      switch value {
      case .bool(let value):
        guard let value else { continue }
        items.append(URLQueryItem(name: encode(key, component: .parameter), value: encode("\(value)", component: .parameter)))
      case .integer(let value):
        guard let value else { continue }
        items.append(URLQueryItem(name: encode(key, component: .parameter), value: encode("\(value)", component: .parameter)))
      case .string(let value):
        guard let value else { continue }
        items.append(URLQueryItem(name: encode(key, component: .parameter), value: encode("\(value)", component: .parameter)))
      case .array(let values):
        guard let values else { continue }
        for value in values {
          items.append(URLQueryItem(name: encode(key, component: .parameter), value: encode(value.description, component: .parameter)))
        }
      }
    }
    return items
  }

  private static func encode(_ string: String, component: XRPCComponent) -> String {
    switch component {
    case .nsid:
      string.addingPercentEncoding(withAllowedCharacters: .nsidAllowed) ?? string
    case .parameter:
      string.addingPercentEncoding(withAllowedCharacters: .parameterAllowed) ?? string
    }
  }
}
