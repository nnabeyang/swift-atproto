import Foundation
import HTTPTypes

extension HTTPField.Name {
  static var atprotoProxy: Self { .init("atproto-proxy")! }
}

public protocol _XRPCCallable: Sendable {
  var oauthSession: (any OAuthSession)? { get }
  func getProxy(nsid: String) -> String?
  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data
  func call<X: XRPCQuery>(_ request: X.Type, input: X.Input.Query) async throws -> X.ResponseBody
  func call<X: XRPCProcedure>(_ request: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody
}

extension _XRPCCallable {
  public var oauthSession: (any OAuthSession)? { nil }
}

extension _XRPCCallable {
  public func call<X: XRPCQuery>(_ query: X.Type, input: X.Input.Query) async throws -> X.ResponseBody {
    let proxy = getProxy(nsid: X.id)
    try enforceRpcScopeGuard(X.self, proxy: proxy)
    var request = try constructRequest(query, input: input)
    if let proxy {
      request.headers[.atprotoProxy] = proxy
    }
    return try await send(query, for: request)
  }

  public func call<X: XRPCProcedure>(_ procedure: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody {
    let proxy = getProxy(nsid: X.id)
    try enforceRpcScopeGuard(X.self, proxy: proxy)
    try enforceRepoScopeGuard(input as? any RepoWriteOperationDescribing)
    try enforceBlobScopeGuard(input as? XRPCBlobUpload)
    var request = try constructRequest(procedure, input: input)
    if let proxy {
      request.headers[.atprotoProxy] = proxy
    }
    return try await send(procedure, for: request)
  }

  private func enforceRpcScopeGuard<X: XRPCRequest>(_: X.Type, proxy: String?) throws {
    guard let session = oauthSession else { return }
    guard let proxy else { return }
    let lxm = X.requiredRpcLxm()
    guard session.grantedScopes.allowsRpc(lxm: lxm, aud: proxy) else {
      throw OAuthScopeError.insufficientScope(lxm: lxm, aud: proxy)
    }
  }

  private func enforceRepoScopeGuard(_ op: (any RepoWriteOperationDescribing)?) throws {
    guard let session = oauthSession else { return }
    guard let op else { return }
    for req in op.repoWriteRequirements {
      guard session.grantedScopes.allowsRepo(collection: req.collection, action: req.action) else {
        throw OAuthScopeError.insufficientRepoScope(collection: req.collection, action: req.action)
      }
    }
  }

  private func enforceBlobScopeGuard(_ upload: XRPCBlobUpload?) throws {
    guard let session = oauthSession else { return }
    guard let upload else { return }
    guard session.grantedScopes.allowsBlob(mime: upload.mimeType) else {
      throw OAuthScopeError.insufficientBlobScope(mime: upload.mimeType)
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
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .xrpc
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let body: Data
    switch input {
    case let upload as XRPCBlobUpload:
      headerFields[.contentType] = upload.mimeType
      body = upload.data
    case let data as Data:
      headerFields[.contentType] = X.contentType
      body = data
    case .none:
      headerFields[.contentType] = X.contentType
      body = Data()
    default:
      headerFields[.contentType] = X.contentType
      body = try encoder.encode(input)
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
