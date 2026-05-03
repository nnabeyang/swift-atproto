import Foundation
import GermConvenience
import HTTPTypes

public struct XRPCRequestComponents: Sendable {
  public var nsId: String
  public var relativePath: String { "/xrpc/\(nsId)" }
  public var queryItems: [URLQueryItem]
  public var headers: HTTPFields
  public var method: HTTPRequest.Method
  public var body: Data?

  public init(
    nsId: String,
    queryItems: [URLQueryItem],
    headers: HTTPFields,
    method: HTTPRequest.Method,
    body: Data? = nil
  ) {
    self.nsId = nsId
    self.queryItems = queryItems
    self.headers = headers
    self.method = method
    self.body = body
  }

  public func constructUrl(serviceUrl: URL) throws -> BundledHTTPRequest {
    var components = try URLComponents(
      url: serviceUrl,
      resolvingAgainstBaseURL: false
    ).tryUnwrap

    components.path = relativePath
    components.queryItems = queryItems

    return try .init(
      method: method,
      url: components.url.tryUnwrap,
      headerFields: headers,
      body: body
    )
  }
}
