import Foundation
import HTTPTypes

/// An XRPC response with the HTTP metadata needed by protocol-level handling.
///
/// A transport that supports DPoP nonce challenges returns this value from
/// `_XRPCCallable.responseWithMetadata(_:)`, including non-success responses.
/// Existing transports can continue implementing `_XRPCCallable.response(_:)`;
/// its payload is treated as a successful response with no headers.
public struct XRPCResponseComponents: Sendable {
  /// The HTTP status code returned by the service.
  public var statusCode: Int
  /// The HTTP response headers.
  public var headers: HTTPFields
  /// The raw response body.
  public var body: Data

  public init(statusCode: Int, headers: HTTPFields = .init(), body: Data) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }
}

/// A decoded XRPC response body together with the response headers.
///
/// Returned by `_XRPCCallable.callWithHeaders(_:input:destination:requestHeaders:)`
/// for protocols that carry part of a response in headers.
public struct XRPCCallResponse<Body: Sendable>: Sendable {
  /// The decoded response body.
  public var body: Body
  /// The HTTP response headers.
  public var headers: HTTPFields

  public init(body: Body, headers: HTTPFields) {
    self.body = body
    self.headers = headers
  }
}
