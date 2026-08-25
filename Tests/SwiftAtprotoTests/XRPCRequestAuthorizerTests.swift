import ATProtoCrypto
import Foundation
import HTTPTypes
import Testing

@testable import SwiftAtproto

@Suite("XRPC request authorization")
struct XRPCRequestAuthorizerTests {
  @Test("selects credentials from the logical destination")
  func selectsCredentialsByDestination() async throws {
    let authorizationRecorder = AuthorizationRecorder()
    let transportRecorder = RequestRecorder()
    let client = AuthorizingClient(
      serviceEndpoint: URL(string: "https://pds.example")!,
      proxy: "did:web:proxy.example#service",
      authorizer: DestinationAuthorizer(recorder: authorizationRecorder),
      recorder: transportRecorder)
    let spaceDID = try DID(string: "did:plc:space")
    let repoDID = try DID(string: "did:plc:member")

    _ = try await client.call(AuthorizationQuery.self, input: .init())
    _ = try await client.call(
      AuthorizationQuery.self,
      input: .init(),
      destination: .spaceHost(
        did: spaceDID,
        serviceEndpoint: URL(string: "https://space.example")!))
    _ = try await client.call(
      AuthorizationQuery.self,
      input: .init(),
      destination: .repoHost(
        did: repoDID,
        serviceEndpoint: URL(string: "https://repo.example")!))

    let authorizations = await authorizationRecorder.snapshots
    #expect(
      authorizations.map(\.serviceEndpoint.absoluteString) == [
        "https://pds.example", "https://space.example", "https://repo.example",
      ])
    #expect(
      authorizations.allSatisfy {
        $0.request.headers[.atprotoProxy] == "did:web:proxy.example#service"
      })
    #expect(authorizations[0].request.destination == nil)
    #expect(
      authorizations[1].request.destination
        == .spaceHost(
          did: spaceDID,
          serviceEndpoint: URL(string: "https://space.example")!))
    #expect(
      authorizations[2].request.destination
        == .repoHost(
          did: repoDID,
          serviceEndpoint: URL(string: "https://repo.example")!))

    let requests = await transportRecorder.requests
    #expect(requests[0].headers[.authorization] == "Bearer access-token")
    #expect(requests[0].headers[.dpop] == nil)
    #expect(requests[1].headers[.authorization] == "Bearer delegation-token")
    #expect(requests[1].headers[.dpop] == "delegation-proof")
    #expect(requests[2].headers[.authorization] == "DPoP space-credential")
    #expect(requests[2].headers[.dpop] == "credential-proof")
  }

  @Test("passes proofs from ATProtoCrypto and other producers unchanged")
  func acceptsProofStringsFromAnyProducer() async throws {
    let endpoint = URL(string: "https://repo.example")!
    let target = endpoint.appending(path: "xrpc/\(AuthorizationQuery.id)")
    let cryptoProof = try DPoPProof(
      httpMethod: "GET",
      url: target,
      issuedAt: Date(timeIntervalSince1970: 1_738_368_000),
      tokenID: "b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8",
      credential: "space-credential"
    ).signed(with: PrivateKey(type: .p256))

    for proof in [cryptoProof, "consumer-produced-proof"] {
      let recorder = RequestRecorder()
      let client = AuthorizingClient(
        serviceEndpoint: endpoint,
        authorizer: StaticDPoPAuthorizer(proof: proof),
        recorder: recorder)

      _ = try await client.call(AuthorizationQuery.self, input: .init())

      let request = try #require(await recorder.requests.first)
      #expect(request.headers[.authorization] == "DPoP space-credential")
      #expect(request.headers[.dpop] == proof)
    }
  }

  @Test("preserves a procedure body while authorizing")
  func preservesProcedureBody() async throws {
    let recorder = RequestRecorder()
    let client = AuthorizingClient(
      serviceEndpoint: URL(string: "https://pds.example")!,
      authorizer: StaticDPoPAuthorizer(proof: "proof"),
      recorder: recorder)
    let input = AuthorizationProcedureBody(value: "kept")

    _ = try await client.call(AuthorizationProcedure.self, input: input)

    let request = try #require(await recorder.requests.first)
    #expect(request.method == .post)
    #expect(try JSONDecoder().decode(AuthorizationProcedureBody.self, from: #require(request.body)) == input)
  }

  @Test("does not invoke the transport when authorization fails")
  func propagatesAuthorizationErrors() async {
    let recorder = RequestRecorder()
    let client = AuthorizingClient(
      serviceEndpoint: URL(string: "https://pds.example")!,
      authorizer: FailingAuthorizer(),
      recorder: recorder)

    await #expect(throws: AuthorizationFailure.missingCredential) {
      _ = try await client.call(AuthorizationQuery.self, input: .init())
    }
    #expect(await recorder.requests.isEmpty)
  }

  @Test("bridges legacy bearer tokens for calls and subscriptions")
  func migratesLegacyBearerTokens() async throws {
    let recorder = RequestRecorder()
    let client = LegacyAuthorizationClient(recorder: recorder)

    _ = try await client.call(AuthorizationQuery.self, input: .init())
    let unary = try #require(await recorder.requests.first)
    #expect(unary.headers[.authorization] == "Bearer raw-token")

    let subscription = try await client.prepareSubscriptionRequest(
      .init(nsId: "com.example.subscribe", queryItems: [], headers: .init()))
    #expect(subscription.headers[.authorization] == "Bearer raw-token")
  }

  @Test("keeps credential values out of descriptions and reflection")
  func redactsCredentialValues() {
    let credentials: [XRPCCredential] = [
      .accessToken("access-secret"),
      .spaceDelegationToken("delegation-secret"),
      .spaceCredential("credential-secret"),
      .clientAttestation("attestation-secret"),
    ]

    for credential in credentials {
      let secret = credential.value
      #expect(!credential.description.contains(secret))
      #expect(!credential.debugDescription.contains(secret))
      #expect(!String(reflecting: credential).contains(secret))
      #expect(
        !Mirror(reflecting: credential).children.contains {
          String(describing: $0.value).contains(secret)
        })
    }
  }
}

private struct DestinationAuthorizer: XRPCRequestAuthorizer {
  let recorder: AuthorizationRecorder

  func authorize(
    _ requestComponents: XRPCRequestComponents,
    serviceEndpoint: URL
  ) async throws -> XRPCRequestComponents {
    await recorder.record(requestComponents, serviceEndpoint: serviceEndpoint)
    var request = requestComponents
    let credential: XRPCCredential
    let proof: String?
    switch request.destination {
    case nil:
      credential = .accessToken("access-token")
      proof = nil
    case .spaceHost:
      credential = .spaceDelegationToken("delegation-token")
      proof = "delegation-proof"
    case .repoHost:
      credential = .spaceCredential("space-credential")
      proof = "credential-proof"
    }
    switch credential {
    case .accessToken(let token), .spaceDelegationToken(let token):
      request.headers[.authorization] = "Bearer \(token)"
    case .spaceCredential(let token):
      request.headers[.authorization] = "DPoP \(token)"
    case .clientAttestation:
      break
    }
    request.headers[.dpop] = proof
    return request
  }
}

private struct StaticDPoPAuthorizer: XRPCRequestAuthorizer {
  let proof: String

  func authorize(
    _ requestComponents: XRPCRequestComponents,
    serviceEndpoint _: URL
  ) async throws -> XRPCRequestComponents {
    var request = requestComponents
    request.headers[.authorization] = "DPoP space-credential"
    request.headers[.dpop] = proof
    return request
  }
}

private struct FailingAuthorizer: XRPCRequestAuthorizer {
  func authorize(
    _: XRPCRequestComponents,
    serviceEndpoint _: URL
  ) async throws -> XRPCRequestComponents {
    throw AuthorizationFailure.missingCredential
  }
}

private enum AuthorizationFailure: Error, Equatable {
  case missingCredential
}

private struct AuthorizingClient: ATPClientProtocol {
  let serviceEndpoint: URL
  let proxy: String?
  let authorizer: any XRPCRequestAuthorizer
  let recorder: RequestRecorder
  let decoder = JSONDecoder()

  init(
    serviceEndpoint: URL,
    proxy: String? = nil,
    authorizer: any XRPCRequestAuthorizer,
    recorder: RequestRecorder
  ) {
    self.serviceEndpoint = serviceEndpoint
    self.proxy = proxy
    self.authorizer = authorizer
    self.recorder = recorder
  }

  func getProxy(nsid _: String) -> String? { proxy }
  func getAuthorization(endpoint _: String) -> String? { nil }
  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func refreshSession() async -> Bool { false }

  func authorize(
    _ requestComponents: XRPCRequestComponents,
    serviceEndpoint: URL
  ) async throws -> XRPCRequestComponents {
    try await authorizer.authorize(requestComponents, serviceEndpoint: serviceEndpoint)
  }

  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data {
    await recorder.record(requestComponents)
    return Data()
  }
}

private struct LegacyAuthorizationClient: ATPClientProtocol, XRPCSubscriptionCallable {
  let recorder: RequestRecorder
  let serviceEndpoint = URL(string: "https://pds.example")!
  let decoder = JSONDecoder()
  let subscriptionTransport: any XRPCSubscriptionTransport = UnusedSubscriptionTransport()

  func getProxy(nsid _: String) -> String? { nil }
  func getAuthorization(endpoint _: String) -> String? { "raw-token" }
  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func refreshSession() async -> Bool { false }

  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data {
    await recorder.record(requestComponents)
    return Data()
  }
}

private struct UnusedSubscriptionTransport: XRPCSubscriptionTransport {
  func connect(_: XRPCWebSocketRequest) async throws -> XRPCWebSocketConnection {
    throw AuthorizationFailure.missingCredential
  }
}

private actor AuthorizationRecorder {
  private(set) var snapshots: [AuthorizationSnapshot] = []

  func record(_ request: XRPCRequestComponents, serviceEndpoint: URL) {
    snapshots.append(.init(request: request, serviceEndpoint: serviceEndpoint))
  }
}

private struct AuthorizationSnapshot: Sendable {
  let request: XRPCRequestComponents
  let serviceEndpoint: URL
}

private actor RequestRecorder {
  private(set) var requests: [XRPCRequestComponents] = []

  func record(_ request: XRPCRequestComponents) {
    requests.append(request)
  }
}

private struct AuthorizationQuery: XRPCQuery {
  static let id = "com.example.authorization"
  typealias Input = AuthorizationQueryInput
  typealias ResponseBody = EmptyResponse
  typealias Error = AuthorizationError
}

private struct AuthorizationQueryInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }

  let query = Query()
}

private struct AuthorizationProcedure: XRPCProcedure {
  static let id = "com.example.authorizationProcedure"
  static let contentType = "application/json"
  typealias RequestBody = AuthorizationProcedureBody
  typealias ResponseBody = EmptyResponse
  typealias Error = AuthorizationError
}

private struct AuthorizationProcedureBody: Codable, Sendable, Hashable {
  let value: String
}

private enum AuthorizationError: XRPCError {
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
