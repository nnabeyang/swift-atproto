import Foundation
import Testing

@testable import SwiftAtproto

struct OAuthSessionTests {
  @Test func conformingTypeExposesAllProperties() throws {
    let session = try SampleOAuthSession(
      sessionDidString: "did:web:user.example.com",
      audienceDidString: "did:web:pds.example.com",
      scopeStrings: [
        "atproto",
        "rpc:com.example.foo?aud=did:web:pds.example.com%23service",
      ]
    )
    #expect(session.sessionDid.rawValue == "did:web:user.example.com")
    #expect(session.audienceDid.rawValue == "did:web:pds.example.com")
    #expect(session.grantedScopes.hasAtprotoScope)
    #expect(
      session.grantedScopes.allowsRpc(
        lxm: "com.example.foo", aud: "did:web:pds.example.com#service"))
  }

  @Test func defaultOAuthSessionOnATPClientProtocolIsNil() {
    let client = MinimalATPClient()
    let typeErased: any ATPClientProtocol = client
    #expect(typeErased.oauthSession == nil)
  }

  @Test func clientCanOverrideOAuthSession() throws {
    let session = try SampleOAuthSession(
      sessionDidString: "did:web:user.example.com",
      audienceDidString: "did:web:pds.example.com",
      scopeStrings: ["atproto"]
    )
    let client = OAuthAwareATPClient(session: session)
    let typeErased: any ATPClientProtocol = client
    #expect(typeErased.oauthSession?.sessionDid.rawValue == "did:web:user.example.com")
  }
}

private struct SampleOAuthSession: OAuthSession {
  let sessionDid: DID
  let audienceDid: DID
  let grantedScopes: ScopesSet

  init(sessionDidString: String, audienceDidString: String, scopeStrings: [String]) throws {
    self.sessionDid = try DID(string: sessionDidString)
    self.audienceDid = try DID(string: audienceDidString)
    self.grantedScopes = try ScopesSet(scopeStrings)
  }
}

private struct MinimalATPClient: @unchecked Sendable, ATPClientProtocol {
  let serviceEndpoint = URL(string: "https://example.com")!
  let decoder = JSONDecoder()
  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func getAuthorization(endpoint _: String) -> String? { nil }
  func refreshSession() async -> Bool { false }
  func response(_: XRPCRequestComponents) async throws -> Data { Data() }
}

private struct OAuthAwareATPClient: @unchecked Sendable, ATPClientProtocol {
  let serviceEndpoint = URL(string: "https://example.com")!
  let decoder = JSONDecoder()
  let oauthSession: (any OAuthSession)?

  init(session: some OAuthSession) {
    self.oauthSession = session
  }

  func tokenIsExpired(error _: some XRPCError) -> Bool { false }
  func getAuthorization(endpoint _: String) -> String? { nil }
  func refreshSession() async -> Bool { false }
  func response(_: XRPCRequestComponents) async throws -> Data { Data() }
}
