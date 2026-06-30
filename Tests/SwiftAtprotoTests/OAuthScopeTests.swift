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

struct RpcScopeTests {
  @Test func parsePositionalAndAud() throws {
    let scope = try RpcScope(string: "rpc:com.example.service?aud=did:web:example.com%23service_id")
    #expect(scope.lxm == ["com.example.service"])
    #expect(scope.aud == "did:web:example.com#service_id")
  }

  @Test func parseQueryFormCanonicalizes() throws {
    let scope = try RpcScope(
      string: "rpc?lxm=com.example.method2&lxm=com.example.method1&aud=*")
    #expect(scope.lxm == ["com.example.method1", "com.example.method2"])
    #expect(scope.aud == "*")
  }

  @Test func lxmWildcardCollapsesEvenWithOtherValues() throws {
    let scope = try RpcScope(
      string: "rpc?lxm=com.example.m1&lxm=com.example.m2&lxm=*&aud=did:web:example.com")
    #expect(scope.lxm == ["*"])
  }

  @Test func wildcardLxmAndWildcardAudIsRejected() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:*?aud=*")
    }
  }

  @Test func serializePositionalForSingleLxm() throws {
    let scope = try RpcScope(aud: "did:web:example.com", lxm: ["com.example.method1"])
    #expect(scope.description == "rpc:com.example.method1?aud=did:web:example.com")
  }

  @Test func serializeMultipleLxmAsQuery() throws {
    let scope = try RpcScope(
      aud: "*", lxm: ["com.example.method2", "com.example.method1"])
    #expect(
      scope.description
        == "rpc?lxm=com.example.method1&lxm=com.example.method2&aud=*")
  }

  @Test func serializeEscapesHashInAud() throws {
    let scope = try RpcScope(
      aud: "did:web:example.com#service_id", lxm: ["com.example.method"])
    #expect(
      scope.description == "rpc:com.example.method?aud=did:web:example.com%23service_id")
  }

  @Test func roundTripCanonicalForms() throws {
    let canonical = [
      "rpc:com.example.method1?aud=*",
      "rpc:*?aud=did:web:example.com%23service_id",
      "rpc?lxm=com.example.method1&lxm=com.example.method2&aud=did:web:example.com%23service_id",
    ]
    for input in canonical {
      let scope = try RpcScope(string: input)
      #expect(scope.description == input, "round-trip mismatch for \(input)")
    }
  }

  @Test func missingAudThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:com.example.method")
    }
  }

  @Test func unknownKeyThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:com.example.method?aud=*&extra=value")
    }
  }

  @Test func emptyPositionalThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:?aud=did:web:example.com")
    }
  }

  @Test func emptyAudThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:com.example.method?aud=")
    }
  }

  @Test func emptyLxmValueThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc?lxm=&aud=did:web:example.com")
    }
  }
}
