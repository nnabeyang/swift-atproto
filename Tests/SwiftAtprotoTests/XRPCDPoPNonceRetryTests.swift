import Foundation
import HTTPTypes
import Testing

@testable import SwiftAtproto

@Suite("XRPC DPoP nonce retry")
struct XRPCDPoPNonceRetryTests {
  @Test("rebuilds authorization and retries once after a nonce challenge")
  func retriesOnceWithTheServerNonce() async throws {
    let authorizer = NonceAuthorizerState()
    let transport = MetadataTransport(responses: [
      challenge(nonce: "server-nonce-1"),
      .init(statusCode: 200, body: Data()),
    ])
    let client = NonceRetryClient(authorizer: authorizer, transport: transport)

    _ = try await client.call(NonceQuery.self, input: .init())

    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].headers[.dpop] == "proof-without-server-nonce")
    #expect(requests[1].headers[.dpop] == "proof-with-server-nonce-1")
    #expect(await authorizer.storedNonces == ["server-nonce-1"])
  }

  @Test("stops when the retry receives another nonce challenge")
  func stopsAfterTheSecondChallenge() async {
    let authorizer = NonceAuthorizerState()
    let transport = MetadataTransport(responses: [
      challenge(nonce: "server-nonce-1"),
      challenge(nonce: "server-nonce-2"),
    ])
    let client = NonceRetryClient(authorizer: authorizer, transport: transport)

    do {
      _ = try await client.call(NonceQuery.self, input: .init())
      Issue.record("Expected the second nonce challenge to be returned")
    } catch let error as NonceCallError {
      #expect(error.error == "use_dpop_nonce")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(await transport.requests.count == 2)
    #expect(await authorizer.storedNonces == ["server-nonce-1"])
  }

  @Test("replays the same procedure body after a rejected attempt")
  func safelyReplaysAProcedureBody() async throws {
    let authorizer = NonceAuthorizerState()
    let transport = MetadataTransport(responses: [
      challenge(nonce: "body-nonce"),
      .init(statusCode: 200, body: Data()),
    ])
    let client = NonceRetryClient(authorizer: authorizer, transport: transport)
    let input = NonceProcedureBody(value: "replay exactly")

    _ = try await client.call(NonceProcedure.self, input: input)

    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].method == .post)
    #expect(requests[0].body == requests[1].body)
    #expect(
      try JSONDecoder().decode(
        NonceProcedureBody.self,
        from: #require(requests[1].body)) == input)
  }

  @Test("does not retry without a complete nonce challenge")
  func ignoresIncompleteAndUnrelatedErrors() async {
    for response in [
      challenge(nonce: nil),
      errorResponse(error: "InvalidToken", nonce: "unrelated-nonce"),
    ] {
      let authorizer = NonceAuthorizerState()
      let transport = MetadataTransport(responses: [response])
      let client = NonceRetryClient(authorizer: authorizer, transport: transport)

      await #expect(throws: NonceCallError.self) {
        _ = try await client.call(NonceQuery.self, input: .init())
      }
      #expect(await transport.requests.count == 1)
      #expect(await authorizer.storedNonces.isEmpty)
    }
  }

  @Test("does not retry when the authorizer cannot store the nonce")
  func requiresTheAuthorizerToAcceptTheNonce() async {
    let authorizer = NonceAuthorizerState(acceptsNonce: false)
    let transport = MetadataTransport(responses: [challenge(nonce: "unused-nonce")])
    let client = NonceRetryClient(authorizer: authorizer, transport: transport)

    await #expect(throws: NonceCallError.self) {
      _ = try await client.call(NonceQuery.self, input: .init())
    }
    #expect(await transport.requests.count == 1)
    #expect(await authorizer.storedNonces.isEmpty)
  }

  @Test("keeps the legacy data-only transport path")
  func preservesLegacyResponseClients() async throws {
    let transport = LegacyTransport()
    let client = LegacyResponseClient(transport: transport)

    _ = try await client.call(NonceQuery.self, input: .init())

    #expect(await transport.requestCount == 1)
  }

  private func challenge(nonce: String?) -> XRPCResponseComponents {
    errorResponse(error: "use_dpop_nonce", nonce: nonce)
  }

  private func errorResponse(
    error: String,
    nonce: String?
  ) -> XRPCResponseComponents {
    var headers = HTTPFields()
    headers[.dpopNonce] = nonce
    return .init(
      statusCode: 401,
      headers: headers,
      body: Data(#"{"error":"\#(error)","message":"proof rejected"}"#.utf8))
  }
}

private actor NonceAuthorizerState: XRPCRequestAuthorizer {
  let acceptsNonce: Bool
  private var nonce: String?
  private(set) var storedNonces: [String] = []

  init(acceptsNonce: Bool = true) {
    self.acceptsNonce = acceptsNonce
  }

  func authorize(
    _ requestComponents: XRPCRequestComponents,
    serviceEndpoint _: URL
  ) async throws -> XRPCRequestComponents {
    var request = requestComponents
    request.headers[.authorization] = "DPoP space-credential"
    request.headers[.dpop] = nonce.map { "proof-with-\($0)" } ?? "proof-without-server-nonce"
    return request
  }

  func storeDPoPNonce(
    _ nonce: String,
    for _: XRPCRequestComponents,
    serviceEndpoint _: URL
  ) async throws -> Bool {
    guard acceptsNonce else { return false }
    self.nonce = nonce
    storedNonces.append(nonce)
    return true
  }
}

private actor MetadataTransport {
  private var responses: [XRPCResponseComponents]
  private(set) var requests: [XRPCRequestComponents] = []

  init(responses: [XRPCResponseComponents]) {
    self.responses = responses
  }

  func response(for request: XRPCRequestComponents) throws -> XRPCResponseComponents {
    requests.append(request)
    guard !responses.isEmpty else { throw NonceTestFailure.missingResponse }
    return responses.removeFirst()
  }
}

private struct NonceRetryClient: ATPClientProtocol {
  let authorizer: NonceAuthorizerState
  let transport: MetadataTransport
  let serviceEndpoint = URL(string: "https://repo.example")!
  let decoder = JSONDecoder()

  func getProxy(nsid _: String) -> String? { nil }
  func getAuthorization(endpoint _: String) -> String? { nil }
  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func refreshSession() async -> Bool { false }

  func authorize(
    _ requestComponents: XRPCRequestComponents,
    serviceEndpoint: URL
  ) async throws -> XRPCRequestComponents {
    try await authorizer.authorize(requestComponents, serviceEndpoint: serviceEndpoint)
  }

  func storeDPoPNonce(
    _ nonce: String,
    for requestComponents: XRPCRequestComponents,
    serviceEndpoint: URL
  ) async throws -> Bool {
    try await authorizer.storeDPoPNonce(
      nonce,
      for: requestComponents,
      serviceEndpoint: serviceEndpoint)
  }

  func response(_: XRPCRequestComponents) async throws -> Data {
    throw NonceTestFailure.legacyTransportUsed
  }

  func responseWithMetadata(
    _ requestComponents: XRPCRequestComponents
  ) async throws -> XRPCResponseComponents {
    try await transport.response(for: requestComponents)
  }
}

private actor LegacyTransport {
  private(set) var requestCount = 0

  func respond() -> Data {
    requestCount += 1
    return Data()
  }
}

private struct LegacyResponseClient: _XRPCCallable {
  let transport: LegacyTransport

  func getProxy(nsid _: String) -> String? { nil }

  func response(_: XRPCRequestComponents) async throws -> Data {
    await transport.respond()
  }
}

private enum NonceTestFailure: Error {
  case legacyTransportUsed
  case missingResponse
}

private struct NonceQuery: XRPCQuery {
  static let id = "com.example.nonceQuery"
  typealias Input = NonceQueryInput
  typealias ResponseBody = EmptyResponse
  typealias Error = NonceCallError
}

private struct NonceQueryInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }

  let query = Query()
}

private struct NonceProcedure: XRPCProcedure {
  static let id = "com.example.nonceProcedure"
  static let contentType = "application/json"
  typealias RequestBody = NonceProcedureBody
  typealias ResponseBody = EmptyResponse
  typealias Error = NonceCallError
}

private struct NonceProcedureBody: Codable, Sendable, Hashable {
  let value: String
}

private enum NonceCallError: XRPCError {
  case unexpected(error: String?, message: String?)

  init(error: UnExpectedError) {
    self = .unexpected(error: error.error, message: error.message)
  }

  var error: String? {
    if case .unexpected(let error, _) = self { error } else { nil }
  }

  var message: String? {
    if case .unexpected(_, let message) = self { message } else { nil }
  }
}
