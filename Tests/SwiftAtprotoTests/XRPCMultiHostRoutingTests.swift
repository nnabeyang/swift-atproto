import Foundation
import HTTPTypes
import Testing

@testable import SwiftAtproto

@Suite("XRPC multi-host routing")
struct XRPCMultiHostRoutingTests {
  @Test("one client routes requests to distinct resolved hosts")
  func routesOneClientToMultipleHosts() async throws {
    let recorder = RoutingRequestRecorder()
    let client = RoutingClient(recorder: recorder, proxy: "did:web:proxy.example#service")
    let memberDID = try DID(string: "did:plc:member")
    let authorityDID = try DID(string: "did:plc:authority")
    let firstRepo = XRPCRequestDestination.repoHost(
      did: memberDID,
      serviceEndpoint: URL(string: "https://repo-one.example")!)
    let secondRepo = XRPCRequestDestination.repoHost(
      did: memberDID,
      serviceEndpoint: URL(string: "https://repo-two.example")!)
    let spaceHost = XRPCRequestDestination.spaceHost(
      did: authorityDID,
      serviceEndpoint: URL(string: "https://space.example")!)

    _ = try await client.call(RoutingQuery.self, input: .init(), destination: firstRepo)
    _ = try await client.call(RoutingQuery.self, input: .init(), destination: secondRepo)
    _ = try await client.call(RoutingProcedure.self, input: nil, destination: spaceHost)

    let requests = await recorder.requests
    #expect(requests.map(\.destination) == [firstRepo, secondRepo, spaceHost])
    #expect(
      requests.map { $0.destination?.serviceEndpoint } == [
        URL(string: "https://repo-one.example"),
        URL(string: "https://repo-two.example"),
        URL(string: "https://space.example"),
      ])
    #expect(
      requests.allSatisfy {
        $0.headers[.atprotoProxy] == "did:web:proxy.example#service"
      })
  }

  @Test("calls without a destination preserve the default route")
  func defaultCallHasNoExplicitDestination() async throws {
    let recorder = RoutingRequestRecorder()
    let client = RoutingClient(recorder: recorder)

    _ = try await client.call(RoutingQuery.self, input: .init())
    _ = try await client.call(RoutingProcedure.self, input: nil)

    let requests = await recorder.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.destination == nil })
  }

  @Test("repo and space hosts are derived from DID documents")
  func resolvesDedicatedHosts() async throws {
    let did = try DID(string: "did:plc:authority")
    let resolver = StaticDIDDocumentResolver(
      document: document(
        did: did,
        services: [
          pds("https://repo.example"),
          .init(
            id: "#atproto_space_host",
            type: "AtprotoSpaceHost",
            serviceEndpoint: "https://space.example"),
        ]))

    let repo = try await resolver.resolveRepoHost(for: did)
    let space = try await resolver.resolveSpaceHost(for: did)

    #expect(repo == .repoHost(did: did, serviceEndpoint: URL(string: "https://repo.example")!))
    #expect(space == .spaceHost(did: did, serviceEndpoint: URL(string: "https://space.example")!))
  }

  @Test("space host fallback retains its logical destination")
  func spaceHostFallsBackToPDS() async throws {
    let did = try DID(string: "did:plc:authority")
    let resolver = StaticDIDDocumentResolver(
      document: document(
        did: did,
        services: [pds("https://pds.example")]))

    let destination = try await resolver.resolveSpaceHost(for: did)

    #expect(
      destination
        == .spaceHost(
          did: did,
          serviceEndpoint: URL(string: "https://pds.example")!))
  }

  @Test("document retrieval failures pass through unchanged")
  func documentFailureIsDistinct() async throws {
    let did = try DID(string: "did:plc:member")
    let resolver = FailingDIDDocumentResolver()

    await #expect(throws: ResolutionFailure.offline) {
      _ = try await resolver.resolveRepoHost(for: did)
    }
  }

  @Test("a resolver cannot return another DID's document")
  func rejectsMismatchedDocument() async throws {
    let requested = try DID(string: "did:plc:member")
    let other = try DID(string: "did:plc:other")
    let resolver = StaticDIDDocumentResolver(
      document: document(
        did: other,
        services: [pds("https://other.example")]))

    await expectVerifyError(.invalidDID) {
      _ = try await resolver.resolveRepoHost(for: requested)
    }
  }

  @Test("missing and invalid repo endpoints remain distinguishable")
  func distinguishesRepoEndpointFailures() async throws {
    let did = try DID(string: "did:plc:member")
    let missing = StaticDIDDocumentResolver(document: document(did: did))
    let invalid = StaticDIDDocumentResolver(
      document: document(
        did: did,
        services: [pds("ftp://repo.example")]))

    await expectVerifyError(.missingPDSService) {
      _ = try await missing.resolveRepoHost(for: did)
    }
    await expectVerifyError(.invalidPDSEndpoint) {
      _ = try await invalid.resolveRepoHost(for: did)
    }
  }

  @Test("an invalid dedicated space endpoint does not fall back")
  func rejectsInvalidDedicatedSpaceEndpoint() async throws {
    let did = try DID(string: "did:plc:authority")
    let resolver = StaticDIDDocumentResolver(
      document: document(
        did: did,
        services: [
          pds("https://pds.example"),
          .init(
            id: "#atproto_space_host",
            type: "AtprotoSpaceHost",
            serviceEndpoint: "/xrpc"),
        ]))

    await expectVerifyError(.invalidServiceEndpoint) {
      _ = try await resolver.resolveSpaceHost(for: did)
    }
  }

  @Test("subscriptions continue to use the client's service endpoint")
  func subscriptionUsesDefaultEndpoint() async throws {
    let client = DefaultSubscriptionClient()
    let request = try await client.prepareSubscriptionRequest(
      .init(
        nsId: "com.example.subscribe",
        queryItems: [.init(name: "cursor", value: "1")],
        headers: .init()))

    #expect(request.url.absoluteString == "wss://default.example/xrpc/com.example.subscribe?cursor=1")
  }
}

private actor RoutingRequestRecorder {
  private(set) var requests: [XRPCRequestComponents] = []

  func record(_ request: XRPCRequestComponents) {
    requests.append(request)
  }
}

private struct RoutingClient: _XRPCCallable {
  let recorder: RoutingRequestRecorder
  let proxy: String?

  init(recorder: RoutingRequestRecorder, proxy: String? = nil) {
    self.recorder = recorder
    self.proxy = proxy
  }

  func getProxy(nsid _: String) -> String? { proxy }

  func response(_ requestComponents: XRPCRequestComponents) async throws -> Data {
    await recorder.record(requestComponents)
    return Data()
  }
}

private struct RoutingQuery: XRPCQuery {
  static let id = "com.example.query"
  typealias Input = RoutingQueryInput
  typealias ResponseBody = EmptyResponse
  typealias Error = RoutingError
}

private struct RoutingQueryInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }

  let query = Query()
}

private struct RoutingProcedure: XRPCProcedure {
  static let id = "com.example.procedure"
  static let contentType = "application/json"
  typealias RequestBody = EmptyResponse
  typealias ResponseBody = EmptyResponse
  typealias Error = RoutingError
}

private enum RoutingError: XRPCError {
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

private struct StaticDIDDocumentResolver: DIDDocumentResolver {
  let document: DIDDocument

  func resolveDIDDocument(for _: DID) async throws -> DIDDocument { document }
}

private struct FailingDIDDocumentResolver: DIDDocumentResolver {
  func resolveDIDDocument(for _: DID) async throws -> DIDDocument {
    throw ResolutionFailure.offline
  }
}

private enum ResolutionFailure: Error, Equatable {
  case offline
}

private func document(did: DID, services: [DocService] = []) -> DIDDocument {
  DIDDocument(context: [], did: FormatString(did), service: services)
}

private func pds(_ endpoint: String) -> DocService {
  DocService(
    id: "#atproto_pds",
    type: "AtprotoPersonalDataServer",
    serviceEndpoint: endpoint)
}

private func expectVerifyError(
  _ expected: DIDDocument.VerifyError,
  performing operation: () async throws -> Void
) async {
  do {
    try await operation()
    Issue.record("Expected \(expected)")
  } catch let error as DIDDocument.VerifyError {
    #expect(sameVerifyError(error, expected))
  } catch {
    Issue.record("Expected DIDDocument.VerifyError, got \(error)")
  }
}

private func sameVerifyError(
  _ lhs: DIDDocument.VerifyError,
  _ rhs: DIDDocument.VerifyError
) -> Bool {
  switch (lhs, rhs) {
  case (.missingPDSService, .missingPDSService),
    (.invalidPDSEndpoint, .invalidPDSEndpoint),
    (.invalidDID, .invalidDID),
    (.invalidServiceEndpoint, .invalidServiceEndpoint):
    true
  default:
    false
  }
}

private struct DefaultSubscriptionClient: ATPClientProtocol, XRPCSubscriptionCallable {
  let serviceEndpoint = URL(string: "https://default.example")!
  let decoder = JSONDecoder()
  let subscriptionTransport: any XRPCSubscriptionTransport = UnusedSubscriptionTransport()

  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func getAuthorization(endpoint _: String) -> String? { nil }
  func refreshSession() async -> Bool { false }
  func response(_: XRPCRequestComponents) async throws -> Data { Data() }
}

private struct UnusedSubscriptionTransport: XRPCSubscriptionTransport {
  func connect(_: XRPCWebSocketRequest) async throws -> XRPCWebSocketConnection {
    Issue.record("Unexpected subscription connection")
    return .init(messages: .init { $0.finish() }, close: {})
  }
}
