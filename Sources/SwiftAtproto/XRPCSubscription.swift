import Foundation
import HTTPTypes
import SwiftCbor

/// A Lexicon `subscription` method, generated from its schema.
///
/// Consume one through ``XRPCSubscriptionCallable/subscribe(_:input:)``; see
/// <doc:Subscriptions>.
public protocol XRPCSubscription: Sendable {
  associatedtype Input: XRPCQueryInput
  associatedtype Message: Decodable & Sendable
  associatedtype Error: XRPCError

  static var id: String { get }
  /// Fully-qualified Lexicon references accepted in the event-stream `t` header.
  static var messageTypes: Set<String> { get }
}

extension XRPCSubscription {
  public static func requiredRpcLxm() -> String { id }
}

/// A prepared subscription request, before it is turned into a WebSocket URL.
public struct XRPCSubscriptionRequestComponents: Sendable {
  /// The NSID of the subscription method.
  public var nsId: String
  /// The encoded subscription parameters.
  public var queryItems: [URLQueryItem]
  /// The headers to send, including any proxy header.
  public var headers: HTTPFields

  public init(nsId: String, queryItems: [URLQueryItem], headers: HTTPFields = .init()) {
    self.nsId = nsId
    self.queryItems = queryItems
    self.headers = headers
  }
}

/// The WebSocket handshake a transport is asked to perform.
public struct XRPCWebSocketRequest: Sendable {
  /// The `wss://` (or `ws://`) URL to connect to.
  public var url: URL
  /// The headers to send with the handshake, including `Authorization`.
  public var headers: HTTPFields

  public init(url: URL, headers: HTTPFields = .init()) {
    self.url = url
    self.headers = headers
  }
}

/// A frame received from a WebSocket transport.
///
/// AT Protocol event streams are binary; a `text` frame is a protocol
/// violation and ends the stream.
public enum XRPCWebSocketMessage: Sendable {
  case binary(Data)
  case text(String)
}

/// An open WebSocket connection supplied by a transport.
public struct XRPCWebSocketConnection: Sendable {
  /// The frames arriving on this connection.
  public let messages: AsyncThrowingStream<XRPCWebSocketMessage, any Error>
  private let closeOperation: @Sendable () async -> Void

  public init(
    messages: AsyncThrowingStream<XRPCWebSocketMessage, any Error>,
    close: @escaping @Sendable () async -> Void
  ) {
    self.messages = messages
    closeOperation = close
  }

  /// Closes the connection and ends ``messages``.
  public func close() async {
    await closeOperation()
  }
}

/// The WebSocket stack a client uses for subscriptions.
///
/// This module opens no sockets of its own. Back this with
/// `URLSessionWebSocketTask` on Apple platforms and a NIO-based client on
/// Linux. See <doc:Subscriptions>.
public protocol XRPCSubscriptionTransport: Sendable {
  func connect(_ request: XRPCWebSocketRequest) async throws -> XRPCWebSocketConnection
}

/// The bounds applied to a subscription stream.
public struct XRPCSubscriptionConfiguration: Sendable {
  /// The largest frame accepted before
  /// ``XRPCSubscriptionStreamError/frameTooLarge(limit:)`` is thrown.
  /// Defaults to 2 MiB.
  public var maximumFrameBytes: Int
  /// How many messages are buffered for a slow consumer. Defaults to 16.
  public var bufferCapacity: Int

  public init(maximumFrameBytes: Int = 2 * 1_024 * 1_024, bufferCapacity: Int = 16) {
    precondition(maximumFrameBytes > 0)
    precondition(bufferCapacity > 0)
    self.maximumFrameBytes = maximumFrameBytes
    self.bufferCapacity = bufferCapacity
  }
}

/// A protocol-level failure that terminates a subscription stream.
public enum XRPCSubscriptionStreamError: Error, Sendable, Equatable {
  case textFrame
  case frameTooLarge(limit: Int)
  case malformedFrame
  case invalidHeader
  case unknownMessageType(String)
  case bufferOverflow(limit: Int)
}

/// A client that can consume Lexicon subscriptions.
///
/// ``ATPClientProtocol`` already implements
/// ``prepareSubscriptionRequest(_:)``, so a conforming client usually only
/// supplies ``subscriptionTransport``. See <doc:Subscriptions>.
public protocol XRPCSubscriptionCallable: _XRPCCallable {
  /// The WebSocket stack used to open connections.
  var subscriptionTransport: any XRPCSubscriptionTransport { get }
  var subscriptionConfiguration: XRPCSubscriptionConfiguration { get }
  func prepareSubscriptionRequest(
    _ components: XRPCSubscriptionRequestComponents
  ) async throws -> XRPCWebSocketRequest
}

extension XRPCSubscriptionCallable {
  public var subscriptionConfiguration: XRPCSubscriptionConfiguration { .init() }

  /// Opens a subscription and yields its decoded messages.
  ///
  /// Cancelling the consuming task closes the connection. When the client has
  /// an OAuth session, the granted `rpc` scope is checked before connecting.
  public func subscribe<X: XRPCSubscription>(
    _ subscription: X.Type,
    input: X.Input.Query
  ) -> AsyncThrowingStream<X.Message, any Error> {
    let configuration = subscriptionConfiguration
    return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(configuration.bufferCapacity)) {
      continuation in
      let worker = Task {
        var connection: XRPCWebSocketConnection?
        do {
          let proxy = getProxy(nsid: X.id)
          try enforceSubscriptionScopeGuard(X.self, proxy: proxy)
          var headers = HTTPFields()
          if let proxy {
            headers[.atprotoProxy] = proxy
          }
          let queryItems = input.asParameters.map(Self.makeParameters(params:)) ?? []
          let components = XRPCSubscriptionRequestComponents(
            nsId: X.id, queryItems: queryItems, headers: headers)
          let request = try await prepareSubscriptionRequest(components)
          let connected = try await subscriptionTransport.connect(request)
          connection = connected

          for try await socketMessage in connected.messages {
            try Task.checkCancellation()
            let message: X.Message
            switch socketMessage {
            case .text:
              throw XRPCSubscriptionStreamError.textFrame
            case .binary(let data):
              guard data.count <= configuration.maximumFrameBytes else {
                throw XRPCSubscriptionStreamError.frameTooLarge(
                  limit: configuration.maximumFrameBytes)
              }
              guard let decoded: X.Message = try decodeEventFrame(data, as: X.self) else {
                continue
              }
              message = decoded
            }
            switch continuation.yield(message) {
            case .enqueued:
              break
            case .dropped:
              throw XRPCSubscriptionStreamError.bufferOverflow(
                limit: configuration.bufferCapacity)
            case .terminated:
              throw CancellationError()
            @unknown default:
              throw XRPCSubscriptionStreamError.bufferOverflow(
                limit: configuration.bufferCapacity)
            }
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
        await connection?.close()
      }
      continuation.onTermination = { @Sendable _ in
        worker.cancel()
      }
    }
  }

  private func enforceSubscriptionScopeGuard<X: XRPCSubscription>(
    _: X.Type, proxy: String?
  ) throws {
    guard let session = oauthSession, let proxy else { return }
    guard session.grantedScopes.allowsRpc(lxm: X.requiredRpcLxm(), aud: proxy) else {
      throw OAuthScopeError.insufficientScope(lxm: X.requiredRpcLxm(), aud: proxy)
    }
  }

  private func decodeEventFrame<X: XRPCSubscription>(
    _ data: Data, as subscription: X.Type
  ) throws -> X.Message? {
    let headerDecoder = ATProtoCbor.decoder()
    let headerResult = try headerDecoder.decodePrefix(EventHeader.self, from: data)
    guard headerResult.bytesConsumed < data.count else {
      throw XRPCSubscriptionStreamError.malformedFrame
    }
    let payload = data.dropFirst(headerResult.bytesConsumed)

    switch headerResult.value.op {
    case 1:
      guard let fragment = headerResult.value.t else {
        throw XRPCSubscriptionStreamError.invalidHeader
      }
      let fullType = fragment.hasPrefix("#") ? X.id + fragment : fragment
      guard X.messageTypes.contains(fullType) else { return nil }
      let decoder = ATProtoCbor.decoder()
      decoder.userInfo[.atprotoLexiconDecodingMode] = LexiconDecodingMode.permissive
      decoder.userInfo[.atprotoSubscriptionMessageType] = fullType
      return try decoder.decode(X.Message.self, from: Data(payload))
    case -1:
      let decoder = ATProtoCbor.decoder()
      let error = try decoder.decode(UnExpectedError.self, from: Data(payload))
      throw X.Error(error: error)
    default:
      // Unknown operations are ignored only after both CBOR objects validate.
      let decoder = ATProtoCbor.decoder()
      _ = try decoder.decode(DiscardedEventPayload.self, from: Data(payload))
      return nil
    }
  }
}

private struct EventHeader: Decodable {
  let op: Int
  let t: String?
}

private struct DiscardedEventPayload: Decodable {}

extension CodingUserInfoKey {
  public static let atprotoSubscriptionMessageType = CodingUserInfoKey(
    rawValue: "com.nnabeyang.swift-atproto.subscription-message-type"
  )!
}
