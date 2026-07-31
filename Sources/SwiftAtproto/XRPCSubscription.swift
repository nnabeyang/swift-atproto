import Foundation
import HTTPTypes
import SwiftCbor

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

public struct XRPCSubscriptionRequestComponents: Sendable {
  public var nsId: String
  public var queryItems: [URLQueryItem]
  public var headers: HTTPFields

  public init(nsId: String, queryItems: [URLQueryItem], headers: HTTPFields = .init()) {
    self.nsId = nsId
    self.queryItems = queryItems
    self.headers = headers
  }
}

public struct XRPCWebSocketRequest: Sendable {
  public var url: URL
  public var headers: HTTPFields

  public init(url: URL, headers: HTTPFields = .init()) {
    self.url = url
    self.headers = headers
  }
}

public enum XRPCWebSocketMessage: Sendable {
  case binary(Data)
  case text(String)
}

public struct XRPCWebSocketConnection: Sendable {
  public let messages: AsyncThrowingStream<XRPCWebSocketMessage, any Error>
  private let closeOperation: @Sendable () async -> Void

  public init(
    messages: AsyncThrowingStream<XRPCWebSocketMessage, any Error>,
    close: @escaping @Sendable () async -> Void
  ) {
    self.messages = messages
    closeOperation = close
  }

  public func close() async {
    await closeOperation()
  }
}

public protocol XRPCSubscriptionTransport: Sendable {
  func connect(_ request: XRPCWebSocketRequest) async throws -> XRPCWebSocketConnection
}

public struct XRPCSubscriptionConfiguration: Sendable {
  public var maximumFrameBytes: Int
  public var bufferCapacity: Int

  public init(maximumFrameBytes: Int = 2 * 1_024 * 1_024, bufferCapacity: Int = 16) {
    precondition(maximumFrameBytes > 0)
    precondition(bufferCapacity > 0)
    self.maximumFrameBytes = maximumFrameBytes
    self.bufferCapacity = bufferCapacity
  }
}

public enum XRPCSubscriptionStreamError: Error, Sendable, Equatable {
  case textFrame
  case frameTooLarge(limit: Int)
  case malformedFrame
  case invalidHeader
  case unknownMessageType(String)
  case bufferOverflow(limit: Int)
}

public protocol XRPCSubscriptionCallable: _XRPCCallable {
  var subscriptionTransport: any XRPCSubscriptionTransport { get }
  var subscriptionConfiguration: XRPCSubscriptionConfiguration { get }
  func prepareSubscriptionRequest(
    _ components: XRPCSubscriptionRequestComponents
  ) async throws -> XRPCWebSocketRequest
}

extension XRPCSubscriptionCallable {
  public var subscriptionConfiguration: XRPCSubscriptionConfiguration { .init() }

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
