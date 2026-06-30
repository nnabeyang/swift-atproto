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
