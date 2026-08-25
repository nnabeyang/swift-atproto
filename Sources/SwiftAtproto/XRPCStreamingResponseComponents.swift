import Foundation
import HTTPTypes

/// An XRPC response whose body can be consumed incrementally.
public struct XRPCStreamingResponseComponents: Sendable {
  /// The HTTP status code returned by the service.
  public var statusCode: Int
  /// The HTTP response headers.
  public var headers: HTTPFields
  /// The pull-driven response body.
  public var body: XRPCBody

  /// Creates an incremental response with its HTTP metadata.
  public init(
    statusCode: Int,
    headers: HTTPFields = .init(),
    body: XRPCBody
  ) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }
}

/// A method whose Lexicon output is an uninterpreted binary payload.
public protocol XRPCBinaryResponseRequest: XRPCRequest where ResponseBody == Data {}

/// An XRPC client transport capable of returning an incremental response body.
///
/// Implement ``responseStreamWithMetadata(_:)``. The compatibility methods
/// required by `_XRPCCallable` collect the stream for existing `Data` APIs.
public protocol XRPCStreamingCallable: _XRPCCallable {
  /// Sends a prepared request and returns its response without buffering its
  /// body.
  func responseStreamWithMetadata(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCStreamingResponseComponents
}

extension XRPCStreamingCallable {
  /// Sends a prepared request and collects its successful body into memory.
  public func response(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> Data {
    try await responseWithMetadata(requestComponents).body
  }

  /// Sends a prepared request and collects its body while retaining metadata.
  public func responseWithMetadata(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCResponseComponents {
    let response = try await responseStreamWithMetadata(requestComponents)
    return try await XRPCResponseComponents(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body.collect(upTo: .max))
  }
}
