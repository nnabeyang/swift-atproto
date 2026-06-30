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
      string: "rpc?lxm=com.example.m1&lxm=com.example.m2&lxm=*&aud=did:web:example.com%23service")
    #expect(scope.lxm == ["*"])
  }

  @Test func wildcardLxmAndWildcardAudIsRejected() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:*?aud=*")
    }
  }

  @Test func serializePositionalForSingleLxm() throws {
    let scope = try RpcScope(aud: "did:web:example.com#service", lxm: ["com.example.method1"])
    #expect(scope.description == "rpc:com.example.method1?aud=did:web:example.com%23service")
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

  @Test func invalidAudienceThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:com.example.method?aud=not-a-did")
    }
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:com.example.method?aud=did:web:example.com")
    }
  }

  @Test func invalidLxmThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:com.example.*?aud=did:web:example.com%23service")
    }
    #expect(throws: OAuthScopeError.self) {
      try RpcScope(string: "rpc:not-an-nsid?aud=did:web:example.com%23service")
    }
  }
}

struct RepoScopeTests {
  @Test func parsePositionalWithDefaultActions() throws {
    let scope = try RepoScope(string: "repo:com.example.post")
    #expect(scope.collection == ["com.example.post"])
    #expect(scope.action == RepoScope.defaultActions)
  }

  @Test func parseQueryFormWithExplicitAction() throws {
    let scope = try RepoScope(string: "repo:com.example.post?action=create")
    #expect(scope.collection == ["com.example.post"])
    #expect(scope.action == [.create])
  }

  @Test func parseAllActionsExplicitDropsBackToDefault() throws {
    let scope = try RepoScope(
      string: "repo:*?action=create&action=update&action=delete")
    #expect(scope.collection == ["*"])
    #expect(scope.action == RepoScope.defaultActions)
  }

  @Test func parseCollectionWildcardCollapses() throws {
    let scope = try RepoScope(
      string: "repo?collection=com.example.foo&collection=*&collection=com.example.bar")
    #expect(scope.collection == ["*"])
  }

  @Test func parseSortsCollectionsAndActions() throws {
    let scope = try RepoScope(
      string: "repo?action=delete&action=create&collection=com.example.bar&collection=com.example.foo")
    #expect(scope.collection == ["com.example.bar", "com.example.foo"])
    #expect(scope.action == [.create, .delete])
  }

  @Test func serializeOmitsDefaultActions() throws {
    let scope = try RepoScope(collection: ["com.example.post"])
    #expect(scope.description == "repo:com.example.post")
  }

  @Test func serializeIncludesNonDefaultActions() throws {
    let scope = try RepoScope(collection: ["com.example.post"], action: [.create])
    #expect(scope.description == "repo:com.example.post?action=create")
  }

  @Test func serializeMultipleCollectionsAsQuery() throws {
    let scope = try RepoScope(
      collection: ["com.example.foo", "com.example.bar"], action: [.create])
    #expect(
      scope.description
        == "repo?collection=com.example.bar&collection=com.example.foo&action=create")
  }

  @Test func roundTripCanonicalForms() throws {
    let canonical = [
      "repo:com.example.post",
      "repo:com.example.post?action=create",
      "repo:*?action=delete",
      "repo?collection=com.example.bar&collection=com.example.foo&action=create",
    ]
    for input in canonical {
      let scope = try RepoScope(string: input)
      #expect(scope.description == input, "round-trip mismatch for \(input)")
    }
  }

  @Test func unknownActionThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RepoScope(string: "repo:com.example.post?action=wibble")
    }
  }

  @Test func emptyPositionalThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RepoScope(string: "repo:?action=create")
    }
  }

  @Test func emptyCollectionValueThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RepoScope(string: "repo?collection=&action=create")
    }
  }

  @Test func invalidCollectionThrows() {
    #expect(throws: OAuthScopeError.self) {
      try RepoScope(string: "repo:com.example.*")
    }
    #expect(throws: OAuthScopeError.self) {
      try RepoScope(string: "repo:not-an-nsid")
    }
  }
}

struct IncludeScopeTests {
  @Test func parsePositionalNsid() throws {
    let scope = try IncludeScope(string: "include:com.example.foo.auth")
    #expect(scope.nsid == "com.example.foo.auth")
    #expect(scope.aud == nil)
  }

  @Test func parseWithAud() throws {
    let scope = try IncludeScope(
      string: "include:com.example.foo.auth?aud=did:web:example.com%23service")
    #expect(scope.nsid == "com.example.foo.auth")
    #expect(scope.aud == "did:web:example.com#service")
  }

  @Test func serializeWithoutAud() throws {
    let scope = try IncludeScope(nsid: "com.example.foo.auth")
    #expect(scope.description == "include:com.example.foo.auth")
  }

  @Test func serializeWithAud() throws {
    let scope = try IncludeScope(
      nsid: "com.example.foo.auth", aud: "did:web:example.com#service")
    #expect(scope.description == "include:com.example.foo.auth?aud=did:web:example.com%23service")
  }

  @Test func roundTripCanonicalForms() throws {
    let canonical = [
      "include:com.example.foo.auth",
      "include:com.example.foo.auth?aud=*",
      "include:com.example.foo.auth?aud=did:web:example.com%23service",
    ]
    for input in canonical {
      let scope = try IncludeScope(string: input)
      #expect(scope.description == input, "round-trip mismatch for \(input)")
    }
  }

  @Test func invalidNsidThrows() {
    #expect(throws: OAuthScopeError.self) {
      try IncludeScope(nsid: "not-an-nsid")
    }
  }

  @Test func parentAuthorityAllowsSibling() throws {
    let scope = try IncludeScope(nsid: "com.example.foo.auth")
    #expect(scope.isParentAuthorityOf("com.example.foo.identifier") == true)
  }

  @Test func parentAuthorityAllowsDeeperChild() throws {
    let scope = try IncludeScope(nsid: "com.example.foo.auth")
    #expect(scope.isParentAuthorityOf("com.example.foo.bar.baz") == true)
  }

  @Test func parentAuthorityRejectsParentSibling() throws {
    let scope = try IncludeScope(nsid: "com.example.foo.auth")
    #expect(scope.isParentAuthorityOf("com.example.bar") == false)
    #expect(scope.isParentAuthorityOf("com.example.bar.something") == false)
  }

  @Test func parentAuthorityRejectsSelfPrefixWithoutChild() throws {
    let scope = try IncludeScope(nsid: "com.example.foo.auth")
    #expect(scope.isParentAuthorityOf("com.example.foo") == false)
  }

  @Test func parentAuthorityRejectsWildcard() throws {
    let scope = try IncludeScope(nsid: "com.example.foo.auth")
    #expect(scope.isParentAuthorityOf("*") == false)
  }

  @Test func emptyPositionalThrows() {
    #expect(throws: OAuthScopeError.self) {
      try IncludeScope(string: "include:")
    }
    #expect(throws: OAuthScopeError.self) {
      try IncludeScope(string: "include:?aud=did:web:example.com")
    }
  }

  @Test func emptyAudThrows() {
    #expect(throws: OAuthScopeError.self) {
      try IncludeScope(string: "include:com.example.foo.auth?aud=")
    }
  }
}

struct IncludeScopeExpandTests {
  @Test func expandsRpcWithInheritAud() throws {
    let include = try IncludeScope(
      nsid: "com.example.auth.scope", aud: "did:web:example.com#service")
    let permissions = [
      LexPermission(
        resource: .rpc,
        inheritAud: true,
        lxm: ["com.example.auth.foo"]
      )
    ]
    let scopes = try include.expand(permissions)
    #expect(
      scopes == ["rpc:com.example.auth.foo?aud=did:web:example.com%23service"])
  }

  @Test func expandsRpcWithWildcardAud() throws {
    let include = try IncludeScope(nsid: "com.example.auth.scope")
    let permissions = [
      LexPermission(
        resource: .rpc,
        aud: "*",
        lxm: ["com.example.auth.foo"]
      )
    ]
    let scopes = try include.expand(permissions)
    #expect(scopes == ["rpc:com.example.auth.foo?aud=*"])
  }

  @Test func expandsRepo() throws {
    let include = try IncludeScope(nsid: "com.example.auth.scope")
    let permissions = [
      LexPermission(
        resource: .repo,
        action: [.create],
        collection: ["com.example.auth.record"]
      )
    ]
    let scopes = try include.expand(permissions)
    #expect(scopes == ["repo:com.example.auth.record?action=create"])
  }

  @Test func expandsRepoWithDefaultActionsOmitted() throws {
    let include = try IncludeScope(nsid: "com.example.auth.scope")
    let permissions = [
      LexPermission(
        resource: .repo,
        action: [.create, .update, .delete],
        collection: ["com.example.auth.record"]
      )
    ]
    let scopes = try include.expand(permissions)
    #expect(scopes == ["repo:com.example.auth.record"])
  }

  @Test func rejectsRpcWithSpecificAudInPermissionSet() {
    #expect(throws: OAuthScopeError.self) {
      let include = try IncludeScope(nsid: "com.example.auth.scope")
      let permissions = [
        LexPermission(
          resource: .rpc,
          aud: "did:web:example.com#service",
          lxm: ["com.example.auth.foo"]
        )
      ]
      _ = try include.expand(permissions)
    }
  }

  @Test func rejectsRpcInheritAudWithoutIncludeAud() {
    #expect(throws: OAuthScopeError.self) {
      let include = try IncludeScope(nsid: "com.example.auth.scope")
      let permissions = [
        LexPermission(
          resource: .rpc,
          inheritAud: true,
          lxm: ["com.example.auth.foo"]
        )
      ]
      _ = try include.expand(permissions)
    }
  }

  @Test func rejectsNsidOutsideAuthority() {
    #expect(throws: OAuthScopeError.self) {
      let include = try IncludeScope(nsid: "com.example.auth.scope")
      let permissions = [
        LexPermission(
          resource: .rpc,
          inheritAud: true,
          lxm: ["com.other.namespace.foo"]
        )
      ]
      let scope = try IncludeScope(
        nsid: "com.example.auth.scope", aud: "did:web:example.com#service")
      _ = try scope.expand(permissions)
      _ = include
    }
  }

  @Test func rejectsUnsupportedResource() {
    #expect(throws: OAuthScopeError.self) {
      let include = try IncludeScope(nsid: "com.example.auth.scope")
      let permissions = [
        LexPermission(resource: LexPermissionResource(rawValue: "blob"))
      ]
      _ = try include.expand(permissions)
    }
  }

  @Test func expandsMixedRpcAndRepo() throws {
    let include = try IncludeScope(
      nsid: "com.example.auth.scope", aud: "did:web:example.com#service")
    let permissions = [
      LexPermission(
        resource: .rpc,
        inheritAud: true,
        lxm: ["com.example.auth.foo", "com.example.auth.bar"]
      ),
      LexPermission(
        resource: .repo,
        action: [.create],
        collection: ["com.example.auth.record"]
      ),
    ]
    let scopes = try include.expand(permissions)
    #expect(scopes.count == 2)
    #expect(
      scopes[0]
        == "rpc?lxm=com.example.auth.bar&lxm=com.example.auth.foo&aud=did:web:example.com%23service")
    #expect(scopes[1] == "repo:com.example.auth.record?action=create")
  }

  @Test func expandsFromPermissionSetType() throws {
    let include = try IncludeScope(
      nsid: "com.example.auth.scope", aud: "did:web:example.com#service")
    let scopes = try include.expand(MatchingPermissionSet.self)
    #expect(scopes == ["rpc:com.example.auth.foo?aud=did:web:example.com%23service"])
  }

  @Test func rejectsMismatchedPermissionSetId() throws {
    let include = try IncludeScope(
      nsid: "com.example.auth.other", aud: "did:web:example.com#service")
    #expect(throws: OAuthScopeError.self) {
      try include.expand(MatchingPermissionSet.self)
    }
  }
}

private enum MatchingPermissionSet: LexPermissionSet {
  static let id = "com.example.auth.scope"
  static let title: String? = nil
  static let detail: String? = nil
  static let permissions: [LexPermission] = [
    LexPermission(resource: .rpc, inheritAud: true, lxm: ["com.example.auth.foo"])
  ]
}

private struct PermissionSetWire: Decodable {
  let defs: Defs

  struct Defs: Decodable {
    let main: Main
  }

  struct Main: Decodable {
    let permissions: [LexPermission]
  }
}

struct EndToEndScopeExpansionTests {
  private static let authCreatePostsJSON = #"""
    {
      "lexicon": 1,
      "id": "com.example.authCreatePosts",
      "defs": {
        "main": {
          "type": "permission-set",
          "title": "Create Example Posts",
          "detail": "Can not update or delete posts.",
          "permissions": [
            {
              "type": "permission",
              "resource": "rpc",
              "inheritAud": true,
              "lxm": [
                "com.example.video.uploadVideo",
                "com.example.video.getJobStatus",
                "com.example.video.getUploadLimits"
              ]
            },
            {
              "type": "permission",
              "resource": "repo",
              "action": ["create"],
              "collection": [
                "com.example.feed.post",
                "com.example.feed.postgate",
                "com.example.feed.threadgate"
              ]
            }
          ]
        }
      }
    }
    """#

  @Test func expandsAuthCreatePostsAgainstCanonicalScopes() throws {
    let wire = try JSONDecoder().decode(
      PermissionSetWire.self, from: Data(Self.authCreatePostsJSON.utf8))
    let include = try IncludeScope(
      nsid: "com.example.authCreatePosts", aud: "did:web:example.com#service")
    let scopes = try include.expand(wire.defs.main.permissions)
    #expect(scopes.count == 2)
    #expect(
      scopes[0]
        == "rpc?lxm=com.example.video.getJobStatus&lxm=com.example.video.getUploadLimits&lxm=com.example.video.uploadVideo&aud=did:web:example.com%23service"
    )
    #expect(
      scopes[1]
        == "repo?collection=com.example.feed.post&collection=com.example.feed.postgate&collection=com.example.feed.threadgate&action=create"
    )
  }

  @Test func roundTripExpandedScopesParseBack() throws {
    let wire = try JSONDecoder().decode(
      PermissionSetWire.self, from: Data(Self.authCreatePostsJSON.utf8))
    let include = try IncludeScope(
      nsid: "com.example.authCreatePosts", aud: "did:web:example.com#service")
    let scopes = try include.expand(wire.defs.main.permissions)

    let rpc = try RpcScope(string: scopes[0])
    #expect(rpc.aud == "did:web:example.com#service")
    #expect(
      rpc.lxm == [
        "com.example.video.getJobStatus",
        "com.example.video.getUploadLimits",
        "com.example.video.uploadVideo",
      ])
    #expect(rpc.description == scopes[0])

    let repo = try RepoScope(string: scopes[1])
    #expect(repo.action == [.create])
    #expect(
      repo.collection == [
        "com.example.feed.post",
        "com.example.feed.postgate",
        "com.example.feed.threadgate",
      ])
    #expect(repo.description == scopes[1])
  }
}

struct ScopesSetTests {
  @Test func parsesAtprotoAndRpcScopes() throws {
    let set = try ScopesSet([
      "atproto",
      "rpc:com.example.foo?aud=did:web:example.com%23service",
    ])
    #expect(set.hasAtprotoScope)
    #expect(set.rpcScopes.count == 1)
    #expect(set.repoScopes.isEmpty)
    #expect(set.includeScopes.isEmpty)
  }

  @Test func parsesIncludeScope() throws {
    let set = try ScopesSet(["include:com.example.foo.auth?aud=*"])
    #expect(set.includeScopes.count == 1)
    #expect(set.includeScopes[0].nsid == "com.example.foo.auth")
  }

  @Test func unknownPrefixGoesToRawOther() throws {
    let set = try ScopesSet(["transition:generic", "atproto"])
    #expect(set.rawOther.contains("transition:generic"))
    #expect(set.hasAtprotoScope)
  }

  @Test func throwingInitRejectsInvalidScope() {
    #expect(throws: OAuthScopeError.self) {
      _ = try ScopesSet(["rpc:*?aud=*"])
    }
  }

  @Test func rawScopesInitSkipsInvalid() {
    let set = ScopesSet(rawScopes: [
      "atproto",
      "rpc:*?aud=*",
      "rpc:com.example.foo?aud=did:web:example.com%23service",
    ])
    #expect(set.hasAtprotoScope)
    #expect(set.rpcScopes.count == 1)
    #expect(set.rpcScopes[0].lxm == ["com.example.foo"])
  }

  @Test func allowsRpcExactMatch() throws {
    let set = try ScopesSet(["atproto", "rpc:com.example.foo?aud=did:web:example.com%23service"])
    #expect(set.allowsRpc(lxm: "com.example.foo", aud: "did:web:example.com#service"))
    #expect(!set.allowsRpc(lxm: "com.example.bar", aud: "did:web:example.com#service"))
    #expect(!set.allowsRpc(lxm: "com.example.foo", aud: "did:web:other.com"))
  }

  @Test func allowsRpcWildcardLxm() throws {
    let set = try ScopesSet(["atproto", "rpc:*?aud=did:web:example.com%23service"])
    #expect(set.allowsRpc(lxm: "com.example.anything", aud: "did:web:example.com#service"))
    #expect(!set.allowsRpc(lxm: "com.example.anything", aud: "did:web:other.com"))
  }

  @Test func allowsRpcWildcardAud() throws {
    let set = try ScopesSet(["atproto", "rpc:com.example.foo?aud=*"])
    #expect(set.allowsRpc(lxm: "com.example.foo", aud: "did:web:example.com#service"))
    #expect(set.allowsRpc(lxm: "com.example.foo", aud: "did:web:other.com"))
  }

  @Test func allowsRpcReturnsFalseOnEmptyScopes() throws {
    let set = try ScopesSet(["atproto"])
    #expect(!set.allowsRpc(lxm: "com.example.foo", aud: "did:web:example.com"))
  }

  @Test func allowsRepoExactMatch() throws {
    let set = try ScopesSet(["atproto", "repo:com.example.post?action=create"])
    #expect(set.allowsRepo(collection: "com.example.post", action: .create))
    #expect(!set.allowsRepo(collection: "com.example.post", action: .delete))
    #expect(!set.allowsRepo(collection: "com.example.other", action: .create))
  }

  @Test func allowsRepoDefaultActions() throws {
    let set = try ScopesSet(["atproto", "repo:com.example.post"])
    #expect(set.allowsRepo(collection: "com.example.post", action: .create))
    #expect(set.allowsRepo(collection: "com.example.post", action: .update))
    #expect(set.allowsRepo(collection: "com.example.post", action: .delete))
  }

  @Test func allowsRepoCollectionWildcard() throws {
    let set = try ScopesSet(["atproto", "repo:*?action=create"])
    #expect(set.allowsRepo(collection: "com.example.anything", action: .create))
    #expect(!set.allowsRepo(collection: "com.example.anything", action: .update))
  }

  @Test func repoWriteRequirementInitAndEquality() {
    let a = RepoWriteRequirement(collection: "com.example.post", action: .create)
    let b = RepoWriteRequirement(collection: "com.example.post", action: .create)
    let c = RepoWriteRequirement(collection: "com.example.post", action: .delete)
    #expect(a == b)
    #expect(a != c)
    #expect(a.collection == "com.example.post")
    #expect(a.action == .create)
  }

  @Test func conformingTypeReportsRequirements() {
    let op = SampleRepoOp(collection: "com.example.post", action: .create)
    #expect(
      op.repoWriteRequirements == [
        RepoWriteRequirement(collection: "com.example.post", action: .create)
      ])
  }

  @Test func multipleScopesCombineForBroadCoverage() throws {
    let set = try ScopesSet([
      "atproto",
      "rpc:com.example.foo?aud=did:web:example.com%23service",
      "rpc:com.example.bar?aud=did:web:example.com%23service",
      "repo:com.example.post?action=create",
    ])
    #expect(set.allowsRpc(lxm: "com.example.foo", aud: "did:web:example.com#service"))
    #expect(set.allowsRpc(lxm: "com.example.bar", aud: "did:web:example.com#service"))
    #expect(set.allowsRepo(collection: "com.example.post", action: .create))
  }

  @Test func allowsRequireAtprotoScope() throws {
    let set = try ScopesSet([
      "rpc:com.example.foo?aud=did:web:example.com%23service",
      "repo:com.example.post?action=create",
    ])
    #expect(!set.hasAtprotoScope)
    #expect(!set.allowsRpc(lxm: "com.example.foo", aud: "did:web:example.com#service"))
    #expect(!set.allowsRepo(collection: "com.example.post", action: .create))
  }

  @Test func throwingInitRejectsMalformedRawScopes() {
    for scope in ["", "bad scope", "emoji:☺️"] {
      #expect(throws: OAuthScopeError.self) {
        _ = try ScopesSet([scope])
      }
    }
  }

  @Test func rawScopesInitSkipsMalformedRawScopes() {
    let set = ScopesSet(rawScopes: ["", "bad scope", "emoji:☺️", "transition:generic"])
    #expect(set.rawOther == ["transition:generic"])
  }
}

private struct SampleRepoOp: RepoWriteOperationDescribing {
  let collection: String
  let action: LexPermissionAction
  var repoWriteRequirements: [RepoWriteRequirement] {
    [RepoWriteRequirement(collection: collection, action: action)]
  }
}

struct IncludeScopeMatchTests {
  @Test func includeWithoutRegistryDoesNotMatch() throws {
    let set = try ScopesSet([
      "atproto",
      "include:com.example.auth.scope?aud=did:web:pds.example.com%23atproto_pds",
    ])
    #expect(set.includeScopes.count == 1)
    #expect(!set.allowsRpc(lxm: "com.example.auth.foo", aud: "did:web:pds.example.com#atproto_pds"))
  }

  @Test func includeWithRegistryAllowsRpc() throws {
    let set = try ScopesSet(
      [
        "atproto",
        "include:com.example.auth.scope?aud=did:web:pds.example.com%23atproto_pds",
      ],
      permissionSets: [SampleAuthPermissionSet.self]
    )
    #expect(
      set.allowsRpc(lxm: "com.example.auth.foo", aud: "did:web:pds.example.com#atproto_pds"))
    #expect(
      set.allowsRpc(lxm: "com.example.auth.bar", aud: "did:web:pds.example.com#atproto_pds"))
  }

  @Test func includeWithRegistryAllowsRepo() throws {
    let set = try ScopesSet(
      [
        "atproto",
        "include:com.example.auth.scope?aud=did:web:pds.example.com%23atproto_pds",
      ],
      permissionSets: [SampleAuthPermissionSet.self]
    )
    #expect(set.allowsRepo(collection: "com.example.auth.record", action: .create))
    #expect(!set.allowsRepo(collection: "com.example.auth.record", action: .delete))
  }

  @Test func includeWithMismatchedAudFromRegistryIsRejected() throws {
    let set = try ScopesSet(
      [
        "atproto",
        "include:com.example.auth.scope?aud=did:web:pds.example.com%23atproto_pds",
      ],
      permissionSets: [SampleAuthPermissionSet.self]
    )
    #expect(
      !set.allowsRpc(lxm: "com.example.auth.foo", aud: "did:web:other.example.com#atproto_pds"))
  }

  @Test func unknownIncludeNsidSilentlySkipped() throws {
    let set = try ScopesSet(
      ["include:com.unknown.scope?aud=did:web:pds.example.com%23atproto_pds"],
      permissionSets: [SampleAuthPermissionSet.self]
    )
    #expect(set.includeScopes.count == 1)
    #expect(!set.allowsRpc(lxm: "com.unknown.foo", aud: "did:web:pds.example.com#atproto_pds"))
  }

  @Test func rawScopesInitAcceptsRegistry() {
    let set = ScopesSet(
      rawScopes: [
        "atproto",
        "include:com.example.auth.scope?aud=did:web:pds.example.com%23atproto_pds",
        "garbage:invalid",
      ],
      permissionSets: [SampleAuthPermissionSet.self]
    )
    #expect(set.hasAtprotoScope)
    #expect(
      set.allowsRpc(lxm: "com.example.auth.foo", aud: "did:web:pds.example.com#atproto_pds"))
  }

  @Test func throwingInitPropagatesRegisteredPermissionSetExpansionErrors() {
    #expect(
      throws: OAuthScopeError.nsidOutsideAuthority(
        parent: "com.example.bad.scope",
        other: "com.other.auth.foo"
      )
    ) {
      _ = try ScopesSet(
        [
          "atproto",
          "include:com.example.bad.scope?aud=did:web:pds.example.com%23atproto_pds",
        ],
        permissionSets: [BrokenAuthPermissionSet.self]
      )
    }
  }

  @Test func rawScopesInitSkipsRegisteredPermissionSetExpansionErrors() {
    let set = ScopesSet(
      rawScopes: [
        "atproto",
        "include:com.example.bad.scope?aud=did:web:pds.example.com%23atproto_pds",
      ],
      permissionSets: [BrokenAuthPermissionSet.self]
    )
    #expect(set.includeScopes.count == 1)
    #expect(!set.allowsRpc(lxm: "com.other.auth.foo", aud: "did:web:pds.example.com#atproto_pds"))
  }
}

private enum SampleAuthPermissionSet: LexPermissionSet {
  static let id = "com.example.auth.scope"
  static let title: String? = "Sample Auth"
  static let detail: String? = nil
  static let permissions: [LexPermission] = [
    LexPermission(
      resource: .rpc,
      inheritAud: true,
      lxm: ["com.example.auth.foo", "com.example.auth.bar"]
    ),
    LexPermission(
      resource: .repo,
      action: [.create],
      collection: ["com.example.auth.record"]
    ),
  ]
}

private enum BrokenAuthPermissionSet: LexPermissionSet {
  static let id = "com.example.bad.scope"
  static let title: String? = nil
  static let detail: String? = nil
  static let permissions: [LexPermission] = [
    LexPermission(
      resource: .rpc,
      inheritAud: true,
      lxm: ["com.other.auth.foo"]
    )
  ]
}
