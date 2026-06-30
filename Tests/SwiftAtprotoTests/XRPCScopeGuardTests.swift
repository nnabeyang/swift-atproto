import Foundation
import HTTPTypes
import Testing

@testable import SwiftAtproto

struct RequiredRpcLxmTests {
  @Test func requiredRpcLxmReturnsIdForQuery() {
    #expect(StubQuery.requiredRpcLxm() == "com.example.stub.query")
  }

  @Test func requiredRpcLxmReturnsIdForProcedure() {
    #expect(StubProcedure.requiredRpcLxm() == "com.example.stub.procedure")
  }
}

struct StubQueryInput: XRPCQueryInput {
  struct Query: XRPCInputQuery {
    var asParameters: Parameters? { nil }
  }
  var query: Query { Query() }
}

enum StubQuery: XRPCQuery {
  static let id = "com.example.stub.query"
  typealias Input = StubQueryInput
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}

enum StubProcedure: XRPCProcedure {
  static let id = "com.example.stub.procedure"
  static let contentType = "application/json"
  typealias RequestBody = EmptyResponse
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}

struct ScopeGuardEnforcementTests {
  @Test func allowedQueryPassesGuard() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.query?aud=did:web:pds.example.com%23atproto_pds",
    ])
    let client = MockClient(session: session)
    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
  }

  @Test func disallowedQueryThrowsInsufficientScope() async throws {
    let session = try sampleSession(scopes: ["atproto"])
    let client = MockClient(session: session)
    await #expect(
      throws: OAuthScopeError.insufficientScope(
        lxm: "com.example.stub.query",
        aud: "did:web:pds.example.com#atproto_pds"
      )
    ) {
      _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
    }
  }

  @Test func disallowedProcedureThrowsInsufficientScope() async throws {
    let session = try sampleSession(scopes: ["atproto"])
    let client = MockClient(session: session)
    await #expect(
      throws: OAuthScopeError.insufficientScope(
        lxm: "com.example.stub.procedure",
        aud: "did:web:pds.example.com#atproto_pds"
      )
    ) {
      _ = try await client.call(StubProcedure.self, input: nil)
    }
  }

  @Test func nilSessionSkipsGuard() async throws {
    let client = MockClient(session: nil)
    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
    _ = try await client.call(StubProcedure.self, input: nil)
  }

  @Test func nilSessionStillAppliesProxyHeader() async throws {
    let recorder = RequestRecorder()
    let client = MockClient(
      session: nil,
      proxy: "did:web:api.example.com#svc_appview",
      recorder: recorder
    )

    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())

    let request = try #require(recorder.lastRequest)
    #expect(request.headers[HTTPField.Name("atproto-proxy")!] == "did:web:api.example.com#svc_appview")
  }

  @Test func wildcardAudMatches() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.query?aud=*",
    ])
    let client = MockClient(session: session)
    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
  }

  @Test func wildcardLxmMatches() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:*?aud=did:web:pds.example.com%23atproto_pds",
    ])
    let client = MockClient(session: session)
    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
  }

  @Test func audienceMismatchThrows() async throws {
    let session = try sampleSession(
      audienceDidString: "did:web:other.example.com",
      scopes: [
        "atproto",
        "rpc:com.example.stub.query?aud=did:web:pds.example.com%23atproto_pds",
      ]
    )
    let client = MockClient(session: session)
    await #expect(
      throws: OAuthScopeError.insufficientScope(
        lxm: "com.example.stub.query",
        aud: "did:web:other.example.com#atproto_pds"
      )
    ) {
      _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
    }
  }

  @Test func proxyAudienceOverridesPDSAudience() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.query?aud=did:web:api.example.com%23svc_appview",
    ])
    let client = MockClient(
      session: session,
      proxy: "did:web:api.example.com#svc_appview"
    )
    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
  }

  @Test func pdsAudienceScopeDoesNotAuthorizeProxyCall() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.query?aud=did:web:pds.example.com%23atproto_pds",
    ])
    let client = MockClient(
      session: session,
      proxy: "did:web:api.example.com#svc_appview"
    )
    await #expect(
      throws: OAuthScopeError.insufficientScope(
        lxm: "com.example.stub.query",
        aud: "did:web:api.example.com#svc_appview"
      )
    ) {
      _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
    }
  }
}

private func sampleSession(
  audienceDidString: String = "did:web:pds.example.com",
  scopes: [String]
) throws -> some OAuthSession {
  try MockOAuthSession(
    sessionDidString: "did:web:user.example.com",
    audienceDidString: audienceDidString,
    scopes: scopes
  )
}

private struct MockOAuthSession: OAuthSession {
  let sessionDid: DID
  let audienceDid: DID
  let grantedScopes: ScopesSet

  init(sessionDidString: String, audienceDidString: String, scopes: [String]) throws {
    self.sessionDid = try DID(string: sessionDidString)
    self.audienceDid = try DID(string: audienceDidString)
    self.grantedScopes = try ScopesSet(scopes)
  }
}

private struct MockClient: @unchecked Sendable, ATPClientProtocol {
  let serviceEndpoint = URL(string: "https://example.com")!
  let decoder = JSONDecoder()
  let oauthSession: (any OAuthSession)?
  let proxy: String?
  let recorder: RequestRecorder?

  init(session: (any OAuthSession)?, proxy: String? = nil, recorder: RequestRecorder? = nil) {
    self.oauthSession = session
    self.proxy = proxy
    self.recorder = recorder
  }

  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func getProxy(nsid _: String) -> String? { proxy }
  func getAuthorization(endpoint _: String) -> String? { nil }
  func refreshSession() async -> Bool { false }
  func response(_ request: XRPCRequestComponents) async throws -> Data {
    recorder?.lastRequest = request
    return Data("{}".utf8)
  }
}

private final class RequestRecorder: @unchecked Sendable {
  var lastRequest: XRPCRequestComponents?
}

struct EndToEndOAuthScopeGuardTests {
  @Test func permissionSetExpandedScopesGateXrpcCalls() async throws {
    let permissions = [
      LexPermission(
        resource: .rpc,
        inheritAud: true,
        lxm: ["com.example.stub.query"]
      )
    ]
    let include = try IncludeScope(
      nsid: "com.example.stub.scope",
      aud: "did:web:pds.example.com#atproto_pds"
    )
    let expandedScopes = try include.expand(permissions)
    let grantedScopes = try ScopesSet(["atproto"] + expandedScopes)
    let session = PrebuiltScopesSession(
      sessionDid: try DID(string: "did:web:user.example.com"),
      audienceDid: try DID(string: "did:web:pds.example.com"),
      grantedScopes: grantedScopes
    )
    let client = MockClient(session: session)

    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())

    await #expect(
      throws: OAuthScopeError.insufficientScope(
        lxm: "com.example.stub.procedure",
        aud: "did:web:pds.example.com#atproto_pds"
      )
    ) {
      _ = try await client.call(StubProcedure.self, input: nil)
    }
  }

  @Test func unknownGrantedScopeStringsStillAllowSession() async throws {
    let grantedScopes = ScopesSet(rawScopes: [
      "atproto",
      "transition:generic",
      "rpc:com.example.stub.query?aud=did:web:pds.example.com%23atproto_pds",
    ])
    let session = PrebuiltScopesSession(
      sessionDid: try DID(string: "did:web:user.example.com"),
      audienceDid: try DID(string: "did:web:pds.example.com"),
      grantedScopes: grantedScopes
    )
    let client = MockClient(session: session)
    _ = try await client.call(StubQuery.self, input: StubQueryInput.Query())
    #expect(grantedScopes.hasAtprotoScope)
    #expect(grantedScopes.rawOther.contains("transition:generic"))
  }
}

private struct PrebuiltScopesSession: OAuthSession {
  let sessionDid: DID
  let audienceDid: DID
  let grantedScopes: ScopesSet
}

struct RepoScopeGuardEnforcementTests {
  @Test func sufficientRepoScopePassesGuard() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.repoWrite?aud=did:web:pds.example.com%23atproto_pds",
      "repo:com.example.post?action=create",
    ])
    let client = MockClient(session: session)
    _ = try await client.call(
      StubRepoProcedure.self,
      input: StubRepoInput(collection: "com.example.post", action: .create))
  }

  @Test func insufficientRepoScopeThrows() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.repoWrite?aud=did:web:pds.example.com%23atproto_pds",
    ])
    let client = MockClient(session: session)
    await #expect(
      throws: OAuthScopeError.insufficientRepoScope(
        collection: "com.example.post",
        action: .create
      )
    ) {
      _ = try await client.call(
        StubRepoProcedure.self,
        input: StubRepoInput(collection: "com.example.post", action: .create))
    }
  }

  @Test func wrongActionRepoScopeThrows() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.repoWrite?aud=did:web:pds.example.com%23atproto_pds",
      "repo:com.example.post?action=update",
    ])
    let client = MockClient(session: session)
    await #expect(
      throws: OAuthScopeError.insufficientRepoScope(
        collection: "com.example.post",
        action: .create
      )
    ) {
      _ = try await client.call(
        StubRepoProcedure.self,
        input: StubRepoInput(collection: "com.example.post", action: .create))
    }
  }

  @Test func nonConformingInputSkipsRepoGuard() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.procedure?aud=did:web:pds.example.com%23atproto_pds",
    ])
    let client = MockClient(session: session)
    _ = try await client.call(StubProcedure.self, input: nil)
  }

  @Test func nilSessionSkipsRepoGuard() async throws {
    let client = MockClient(session: nil)
    _ = try await client.call(
      StubRepoProcedure.self,
      input: StubRepoInput(collection: "com.example.post", action: .create))
  }

  @Test func multipleRequirementsAllChecked() async throws {
    let session = try sampleSession(scopes: [
      "atproto",
      "rpc:com.example.stub.repoWriteBatch?aud=did:web:pds.example.com%23atproto_pds",
      "repo:com.example.post?action=create",
    ])
    let client = MockClient(session: session)
    await #expect(
      throws: OAuthScopeError.insufficientRepoScope(
        collection: "com.example.other",
        action: .create
      )
    ) {
      _ = try await client.call(
        StubRepoBatchProcedure.self,
        input: StubRepoBatchInput(items: [
          .init(collection: "com.example.post", action: "create"),
          .init(collection: "com.example.other", action: "create"),
        ]))
    }
  }
}

struct StubRepoInput: Codable, Sendable, Hashable, RepoWriteOperationDescribing {
  let collection: String
  let action: LexPermissionAction
  var repoWriteRequirements: [RepoWriteRequirement] {
    [RepoWriteRequirement(collection: collection, action: action)]
  }
}

enum StubRepoProcedure: XRPCProcedure {
  static let id = "com.example.stub.repoWrite"
  static let contentType = "application/json"
  typealias RequestBody = StubRepoInput
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}

struct StubRepoBatchInput: Codable, Sendable, Hashable, RepoWriteOperationDescribing {
  struct Item: Codable, Sendable, Hashable {
    let collection: String
    let action: String
  }
  let items: [Item]
  var repoWriteRequirements: [RepoWriteRequirement] {
    items.map {
      RepoWriteRequirement(collection: $0.collection, action: LexPermissionAction(rawValue: $0.action))
    }
  }
}

enum StubRepoBatchProcedure: XRPCProcedure {
  static let id = "com.example.stub.repoWriteBatch"
  static let contentType = "application/json"
  typealias RequestBody = StubRepoBatchInput
  typealias ResponseBody = EmptyResponse
  typealias Error = UnExpectedError
}
