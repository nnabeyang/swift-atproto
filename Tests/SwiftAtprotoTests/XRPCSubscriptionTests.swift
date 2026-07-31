import Foundation
import HTTPTypes
import SwiftCbor
import Testing

@testable import SwiftAtproto

@Suite("XRPC subscription runtime")
struct XRPCSubscriptionTests {
  @Test("decodes a header and payload from one binary frame")
  func decodesBinaryFrame() async throws {
    let encoder = CborEncoder(options: .lexicographicallySortedMapKeys)
    let header = try encoder.encode(["op": 1, "t": "#message"] as [String: AnySendable])
    let payload = try encoder.encode(["value": 42])
    let transport = TestSubscriptionTransport(messages: [.binary(header + payload)])
    let client = TestSubscriptionClient(transport: transport)

    var iterator = client.subscribe(TestSubscription.self, input: .init()).makeAsyncIterator()
    let message = try await iterator.next()
    #expect(message == TestMessage(value: 42))
    #expect(try await iterator.next() == nil)
  }

  @Test("rejects text frames")
  func rejectsTextFrame() async {
    let transport = TestSubscriptionTransport(messages: [.text("{}")])
    let client = TestSubscriptionClient(transport: transport)
    var iterator = client.subscribe(TestSubscription.self, input: .init()).makeAsyncIterator()
    await #expect(throws: XRPCSubscriptionStreamError.textFrame) {
      _ = try await iterator.next()
    }
  }
}

private struct TestSubscription: XRPCSubscription {
  static let id = "com.example.subscribe"
  static let messageTypes: Set<String> = ["com.example.subscribe#message"]
  typealias Input = TestInput
  typealias Message = TestMessage
  typealias Error = TestSubscriptionError
}

private struct TestInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }
  let query = Query()
}

private struct TestMessage: Codable, Sendable, Equatable {
  let value: Int
}

private enum TestSubscriptionError: XRPCError {
  case unexpected(error: String?, message: String?)

  init(error: UnExpectedError) {
    self = .unexpected(error: error.error, message: error.message)
  }

  var error: String? {
    if case .unexpected(let error, _) = self { return error }
    return nil
  }

  var message: String? {
    if case .unexpected(_, let message) = self { return message }
    return nil
  }
}

private struct TestSubscriptionTransport: XRPCSubscriptionTransport {
  let values: [XRPCWebSocketMessage]

  init(messages: [XRPCWebSocketMessage]) {
    values = messages
  }

  func connect(_ request: XRPCWebSocketRequest) async throws -> XRPCWebSocketConnection {
    let values = values
    let stream = AsyncThrowingStream<XRPCWebSocketMessage, any Error> { continuation in
      for value in values {
        continuation.yield(value)
      }
      continuation.finish()
    }
    return XRPCWebSocketConnection(messages: stream, close: {})
  }
}

private struct TestSubscriptionClient: XRPCSubscriptionCallable {
  let transport: TestSubscriptionTransport
  var subscriptionTransport: any XRPCSubscriptionTransport { transport }

  func getProxy(nsid: String) -> String? { nil }
  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data { Data() }
  func prepareSubscriptionRequest(
    _ components: XRPCSubscriptionRequestComponents
  ) async throws -> XRPCWebSocketRequest {
    XRPCWebSocketRequest(url: URL(string: "wss://example.com/xrpc/\(components.nsId)")!)
  }
}

private enum AnySendable: Encodable, Sendable {
  case int(Int)
  case string(String)

  init(integerLiteral value: Int) { self = .int(value) }
  init(stringLiteral value: String) { self = .string(value) }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .int(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    }
  }
}

extension AnySendable: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {}
