import Foundation
import HTTPTypes

extension HTTPField.Name {
  static var atprotoProxy: Self { .init("atproto-proxy")! }
  /// A proof of possession for a DPoP-bound authorization credential.
  public static var dpop: Self { .init("dpop")! }
  /// A server-provided nonce required in the next DPoP proof.
  public static var dpopNonce: Self { .init("dpop-nonce")! }
}

/// The minimum a client has to provide in order to make XRPC calls.
///
/// Implement `response(_:)`; the protocol extension implements both `call`
/// overloads on top of it, which is what makes every generated method callable.
/// See <doc:MakingXRPCCalls>.
///
/// This protocol is infrastructure shared with generated code. Conform to
/// ``ATPClientProtocol`` instead of using it directly.
public protocol _XRPCCallable: Sendable {
  /// The OAuth session whose granted scopes gate outgoing calls, or `nil` to
  /// skip scope enforcement entirely. Defaults to `nil`.
  var oauthSession: (any OAuthSession)? { get }
  /// Applies credentials and proof headers after the request and proxy header
  /// have been prepared. The default leaves the request unchanged.
  func authorize(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCRequestComponents
  /// Stores a DPoP nonce for the request's destination when the authorizer can
  /// rebuild its proof. The default returns `false`.
  func storeDPoPNonce(
    _ nonce: String,
    for requestComponents: XRPCRequestComponents
  ) async throws -> Bool
  /// The service to proxy this method to via the `atproto-proxy` header, or
  /// `nil` to send it to the client's own endpoint.
  func getProxy(nsid: String) -> String?
  /// Sends a prepared request and returns the raw response payload.
  ///
  /// This is the only transport-specific requirement. Throw
  /// ``UnExpectedError`` for a failure the method's Lexicon does not describe;
  /// it is converted into the method's own error type.
  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data
  /// Sends a prepared request and returns its response metadata and payload.
  ///
  /// Override this to enable protocol-level handling of non-success responses,
  /// including DPoP nonce challenges. The default wraps ``response(_:)`` as a
  /// successful response with no headers.
  func responseWithMetadata(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCResponseComponents
  /// Calls a query, encoding `input` as query items.
  func call<X: XRPCQuery>(_ request: X.Type, input: X.Input.Query) async throws -> X.ResponseBody
  /// Calls a query at an explicitly resolved destination.
  func call<X: XRPCQuery>(
    _ request: X.Type,
    input: X.Input.Query,
    destination: XRPCRequestDestination
  ) async throws -> X.ResponseBody
  /// Calls a procedure, encoding `input` into the request body.
  func call<X: XRPCProcedure>(_ request: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody
  /// Calls a procedure at an explicitly resolved destination.
  func call<X: XRPCProcedure>(
    _ request: X.Type,
    input: X.RequestBody?,
    destination: XRPCRequestDestination
  ) async throws -> X.ResponseBody
}

extension _XRPCCallable {
  public var oauthSession: (any OAuthSession)? { nil }

  public func authorize(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCRequestComponents {
    requestComponents
  }

  public func storeDPoPNonce(
    _: String,
    for _: XRPCRequestComponents
  ) async throws -> Bool {
    false
  }

  public func responseWithMetadata(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCResponseComponents {
    let body = try await response(requestComponents)
    return .init(statusCode: 200, body: body)
  }
}

extension _XRPCCallable {
  public func call<X: XRPCQuery>(_ query: X.Type, input: X.Input.Query) async throws -> X.ResponseBody {
    try await call(query, input: input, destination: nil)
  }

  public func call<X: XRPCQuery>(
    _ query: X.Type,
    input: X.Input.Query,
    destination: XRPCRequestDestination
  ) async throws -> X.ResponseBody {
    try await call(query, input: input, destination: Optional(destination))
  }

  private func call<X: XRPCQuery>(
    _ query: X.Type,
    input: X.Input.Query,
    destination: XRPCRequestDestination?
  ) async throws -> X.ResponseBody {
    let proxy = getProxy(nsid: X.id)
    try enforceRpcScopeGuard(X.self, proxy: proxy)
    var request = try constructRequest(query, input: input, destination: destination)
    if let proxy {
      request.headers[.atprotoProxy] = proxy
    }
    return try await send(query, for: request)
  }

  public func call<X: XRPCProcedure>(_ procedure: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody {
    try await call(procedure, input: input, destination: nil)
  }

  public func call<X: XRPCProcedure>(
    _ procedure: X.Type,
    input: X.RequestBody?,
    destination: XRPCRequestDestination
  ) async throws -> X.ResponseBody {
    try await call(procedure, input: input, destination: Optional(destination))
  }

  private func call<X: XRPCProcedure>(
    _ procedure: X.Type,
    input: X.RequestBody?,
    destination: XRPCRequestDestination?
  ) async throws -> X.ResponseBody {
    let proxy = getProxy(nsid: X.id)
    try enforceRpcScopeGuard(X.self, proxy: proxy)
    try enforceRepoScopeGuard(input as? any RepoWriteOperationDescribing)
    try enforceBlobScopeGuard(input as? XRPCBlobUpload)
    var request = try constructRequest(procedure, input: input, destination: destination)
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
      let firstResponse = try await perform(request)
      let response: XRPCResponseComponents
      if let nonce = dpopNonceChallenge(in: firstResponse),
        try await storeDPoPNonce(nonce, for: request)
      {
        response = try await perform(request)
      } else {
        response = firstResponse
      }
      let data = try responseBody(from: response)
      if X.ResponseBody.self == EmptyResponse.self {
        return EmptyResponse() as! X.ResponseBody
      }
      if X.ResponseBody.self == Data.self {
        return data as! X.ResponseBody
      }
      let decoder = JSONDecoder()
      decoder.dataDecodingStrategy = .xrpc
      decoder.userInfo[.atprotoLexiconDecodingMode] = LexiconDecodingMode.permissive
      return try decoder.decode(X.ResponseBody.self, from: data)
    } catch let error as UnExpectedError {
      throw X.Error(error: error)
    }
  }

  private func perform(
    _ request: XRPCRequestComponents
  ) async throws -> XRPCResponseComponents {
    let authorizedRequest = try await authorize(request)
    return try await responseWithMetadata(authorizedRequest)
  }

  private func dpopNonceChallenge(in response: XRPCResponseComponents) -> String? {
    guard !(200...299).contains(response.statusCode),
      let nonce = response.headers[.dpopNonce],
      !nonce.isEmpty,
      let error = try? JSONDecoder().decode(UnExpectedError.self, from: response.body),
      error.error == "use_dpop_nonce"
    else {
      return nil
    }
    return nonce
  }

  private func responseBody(from response: XRPCResponseComponents) throws -> Data {
    guard (200...299).contains(response.statusCode) else {
      if let error = try? JSONDecoder().decode(UnExpectedError.self, from: response.body) {
        throw error
      }
      throw UnExpectedError(
        error: nil,
        message: "HTTP request failed with status code \(response.statusCode).")
    }
    return response.body
  }

  func constructRequest<X: XRPCQuery>(
    _ request: X.Type,
    input: X.Input.Query,
    destination: XRPCRequestDestination? = nil,
  ) throws -> XRPCRequestComponents {
    let queryItems = input.asParameters.map({ Self.makeParameters(params: $0) }) ?? .init()
    return .init(
      nsId: X.id,
      queryItems: queryItems,
      headers: .init(
        dictionaryLiteral: (.accept, "json/application")
      ),
      method: .get,
      destination: destination
    )
  }

  func constructRequest<X: XRPCProcedure>(
    _ request: X.Type,
    input: X.RequestBody?,
    destination: XRPCRequestDestination? = nil,
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
      body: body,
      destination: destination
    )
  }

  /// Renders parameters as percent-encoded query items, dropping `nil` values
  /// and expanding arrays into repeated items.
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
