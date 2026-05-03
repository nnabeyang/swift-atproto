import Foundation
import GermConvenience
import HTTPTypes

public protocol _XRPCCallable: Sendable {
  func response(_ requestComponents: XRPCRequestComponents) async throws -> HTTPDataResponse
  func call<X: XRPCQuery>(_ request: X.Type, input: X.Input.Query) async throws -> X.ResponseBody
  func call<X: XRPCProcedure>(_ request: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody
}

extension _XRPCCallable {
  public func call<X: XRPCQuery>(_ request: X.Type, input: X.Input.Query) async throws -> X.ResponseBody {
    var request = try constructRequest(request, input: input)

    request.headers[try .init("atproto-proxy").tryUnwrap] = "did:web:api.bsky.app#bsky_appview"

    let result = try await response(request)
    let decoder = JSONDecoder()
    return try decoder.decode(X.ResponseBody.self, from: result.data)
  }

  public func call<X: XRPCProcedure>(_ procedure: X.Type, input: X.RequestBody?) async throws -> X.ResponseBody {
    var request = try constructRequest(procedure, input: input)

    request.headers[try .init("atproto-proxy").tryUnwrap] = "did:web:api.bsky.app#bsky_appview"

    let result = try await response(request)
    let decoder = JSONDecoder()
    return try decoder.decode(X.ResponseBody.self, from: result.data)
  }

  func constructRequest<X: XRPCQuery>(
    _ request: X.Type,
    input: X.Input.Query,
  ) throws -> XRPCRequestComponents {
    let queryItems = input.asParameters.map({ Self.makeParameters(params: $0) }) ?? .init()
    return .init(
      relativePath: "/xrpc/" + X.id,
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
    encoder.dataEncodingStrategy = Self.dataEncodingStrategy
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
      relativePath: "/xrpc/" + X.id,
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
        items.append(URLQueryItem(name: key, value: "\(value)"))
      case .integer(let value):
        guard let value else { continue }
        items.append(URLQueryItem(name: key, value: "\(value)"))
      case .string(let value):
        guard let value else { continue }
        items.append(URLQueryItem(name: key, value: "\(value)"))
      case .array(let values):
        guard let values else { continue }
        for value in values {
          items.append(URLQueryItem(name: key, value: value.description))
        }
      }
    }
    return items
  }

  private static var dataEncodingStrategy: JSONEncoder.DataEncodingStrategy {
    .custom { data, encoder in
      do {
        if !data.isEmpty, data[0] == 0 {
          try LexLink.dataEncodingStrategy(data: data, encoder: encoder)
          return
        }
      } catch {}
      if let string = String(data: data, encoding: .utf8) {
        try string.encode(to: encoder)
      } else {
        try data.base64Encoded().encode(to: encoder)
      }
    }
  }
}
