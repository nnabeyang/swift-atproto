import Foundation
import HTTPTypes

/// A prepared XRPC request in transport-neutral form.
///
/// A client turns this into whatever its HTTP stack expects; see
/// <doc:MakingXRPCCalls>.
public struct XRPCRequestComponents: Sendable {
  /// The NSID of the method being called.
  public var nsId: String
  /// The path to append to the service endpoint: `/xrpc/<nsid>`.
  public var relativePath: String { "/xrpc/\(nsId)" }
  /// The encoded query parameters, empty for a procedure.
  public var queryItems: [URLQueryItem]
  /// The headers to send, including `Content-Type` and any proxy header.
  public var headers: HTTPFields
  /// `GET` for a query, `POST` for a procedure.
  public var method: HTTPRequest.Method
  /// The encoded request body, or `nil` for a query.
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
}
