import Foundation
import Testing

@testable import SwiftAtproto

struct OAuthScopeSyntaxTests {
  @Test func parsesBarePrefix() {
    let syntax = OAuthScopeSyntax.parse("atproto")
    #expect(syntax.prefix == "atproto")
    #expect(syntax.positional == nil)
    #expect(syntax.params.isEmpty)
  }

  @Test func parsesPositionalOnly() {
    let syntax = OAuthScopeSyntax.parse("rpc:com.example.foo")
    #expect(syntax.prefix == "rpc")
    #expect(syntax.positional == "com.example.foo")
    #expect(syntax.params.isEmpty)
  }

  @Test func parsesPositionalWithQuery() {
    let syntax = OAuthScopeSyntax.parse("rpc:com.example.foo?aud=did:web:example.com")
    #expect(syntax.prefix == "rpc")
    #expect(syntax.positional == "com.example.foo")
    #expect(syntax.params == [OAuthScopeQueryParam(key: "aud", value: "did:web:example.com")])
  }

  @Test func parsesQueryOnly() {
    let syntax = OAuthScopeSyntax.parse("repo?action=create&collection=com.example.post")
    #expect(syntax.prefix == "repo")
    #expect(syntax.positional == nil)
    #expect(
      syntax.params == [
        OAuthScopeQueryParam(key: "action", value: "create"),
        OAuthScopeQueryParam(key: "collection", value: "com.example.post"),
      ])
  }

  @Test func parseDecodesPercentEscapedHash() {
    let syntax = OAuthScopeSyntax.parse(
      "rpc:com.example.svc?aud=did:web:example.com%23service_id")
    #expect(syntax.positional == "com.example.svc")
    #expect(syntax.params == [OAuthScopeQueryParam(key: "aud", value: "did:web:example.com#service_id")])
  }

  @Test func serializeBarePrefix() {
    let syntax = OAuthScopeSyntax(prefix: "atproto")
    #expect(syntax.description == "atproto")
  }

  @Test func serializePreservesAllowedCharacters() {
    let syntax = OAuthScopeSyntax(
      prefix: "rpc",
      positional: "com.example.foo",
      params: [OAuthScopeQueryParam(key: "aud", value: "did:web:example.com")]
    )
    #expect(syntax.description == "rpc:com.example.foo?aud=did:web:example.com")
  }

  @Test func serializeEscapesHashInValue() {
    let syntax = OAuthScopeSyntax(
      prefix: "rpc",
      positional: "com.example.svc",
      params: [OAuthScopeQueryParam(key: "aud", value: "did:web:example.com#service_id")]
    )
    #expect(syntax.description == "rpc:com.example.svc?aud=did:web:example.com%23service_id")
  }

  @Test func roundTripIdempotent() {
    let inputs = [
      "atproto",
      "rpc:com.example.foo",
      "rpc:com.example.foo?aud=did:web:example.com%23service",
      "repo?action=create&collection=com.example.post",
      "include:com.example.bar?aud=*",
    ]
    for input in inputs {
      let parsed = OAuthScopeSyntax.parse(input)
      let serialized = parsed.description
      let reparsed = OAuthScopeSyntax.parse(serialized)
      #expect(parsed == reparsed, "round-trip parse-equality failed for \(input)")
    }
  }
}
