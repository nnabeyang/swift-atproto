import Foundation
import Testing

@testable import SwiftAtproto

@Suite("Permissioned space OAuth scopes")
struct SpaceOAuthScopeTests {
  private let grantor = try! DID(string: "did:plc:alice")
  private let otherAuthority = try! DID(string: "did:plc:forum")
  private let ownSpace = try! SpaceRef(
    string: "at://did:plc:alice/space/com.example.forum/default")
  private let sharedSpace = try! SpaceRef(
    string: "at://did:plc:forum/space/com.example.forum/default")

  @Test("bare scope applies proposal defaults")
  func parsesDefaults() throws {
    let scope = try SpaceScope(string: "space:com.example.forum")

    #expect(scope.spaceType == "com.example.forum")
    #expect(scope.authority == "self")
    #expect(scope.skey == "*")
    #expect(scope.collection == nil)
    #expect(scope.action == [.read, .create, .update, .delete])
    #expect(scope.manage.isEmpty)
    #expect(scope.description == "space:com.example.forum")
  }

  @Test(
    "proposal examples round-trip canonically",
    arguments: [
      "space:com.example.bookmarks",
      "space:com.atmoboards.forum?authority=*",
      "space:com.atmoboards.forum?authority=*&action=read",
      "space:com.atmoboards.forum?authority=*&action=read_self",
      "space:com.atmoboards.forum?authority=*&collection=*",
      "space:com.atmoboards.forum?authority=did:plc:abc123&skey=default&collection=com.atmoboards.thread&action=create&action=update",
      "space:com.atmoboards.forum?authority=*&action=read_self&manage=update&manage=delete",
      "space:com.atmoboards.forum?authority=*&manage=update&manage=delete",
      "space:*?authority=did:plc:abc123",
    ])
  func proposalExamplesRoundTrip(_ example: String) throws {
    #expect(try SpaceScope(string: example).description == example)
  }

  @Test("scope parameters normalize in a stable order")
  func normalizesParameters() throws {
    let scope = try SpaceScope(
      string:
        "space:com.example.forum?manage=delete&authority=*&action=update&collection=com.example.reply&action=read_self&collection=com.example.thread&action=read&manage=update"
    )

    #expect(scope.action == [.read, .update])
    #expect(scope.manage == [.update, .delete])
    #expect(scope.collection == ["com.example.reply", "com.example.thread"])
    #expect(
      scope.description
        == "space:com.example.forum?authority=*&collection=com.example.reply&collection=com.example.thread&action=read&action=update&manage=update&manage=delete"
    )
  }

  @Test("invalid selectors and operations are rejected")
  func rejectsInvalidScopes() {
    #expect(throws: OAuthScopeError.self) { try SpaceScope(string: "space:") }
    #expect(throws: OAuthScopeError.self) {
      try SpaceScope(string: "space:com.example.forum?authority=example.com")
    }
    #expect(throws: OAuthScopeError.self) {
      try SpaceScope(string: "space:com.example.forum?action=publish")
    }
    #expect(throws: OAuthScopeError.duplicateKey("authority")) {
      try SpaceScope(
        string: "space:com.example.forum?authority=self&authority=did:plc:forum")
    }
  }

  @Test("self and wildcard selectors match the intended spaces")
  func matchesSpaceSelectors() throws {
    let ownScopes = try ScopesSet(["atproto", "space:com.example.forum"])
    let readOwn = SpaceScopeRequirement(space: ownSpace, operation: .read(repository: grantor))
    let readShared = SpaceScopeRequirement(space: sharedSpace, operation: .read(repository: grantor))

    #expect(ownScopes.allowsSpace(readOwn, grantedBy: grantor))
    #expect(!ownScopes.allowsSpace(readShared, grantedBy: grantor))

    let wildcard = try ScopesSet([
      "atproto", "space:*?authority=did:plc:forum&action=read",
    ])
    #expect(wildcard.allowsSpace(readShared, grantedBy: grantor))

    let exactKey = try ScopesSet([
      "atproto", "space:com.example.forum?authority=*&skey=other&action=read",
    ])
    #expect(!exactKey.allowsSpace(readShared, grantedBy: grantor))
  }

  @Test("read_self is limited to the grantor and cannot mint delegation tokens")
  func enforcesReadSelf() throws {
    let scopes = try ScopesSet([
      "atproto", "space:com.example.forum?authority=*&action=read_self",
    ])
    let ownRead = SpaceScopeRequirement(space: sharedSpace, operation: .read(repository: grantor))
    let otherRead = SpaceScopeRequirement(
      space: sharedSpace, operation: .read(repository: otherAuthority))
    let delegation = SpaceScopeRequirement(space: sharedSpace, operation: .delegationToken)

    #expect(scopes.allowsSpace(ownRead, grantedBy: grantor))
    #expect(!scopes.allowsSpace(otherRead, grantedBy: grantor))
    #expect(!scopes.allowsSpace(delegation, grantedBy: grantor))

    let read = try ScopesSet([
      "atproto", "space:com.example.forum?authority=*&action=read",
    ])
    #expect(read.allowsSpace(otherRead, grantedBy: grantor))
    #expect(read.allowsSpace(delegation, grantedBy: grantor))
  }

  @Test("omitted collections resolve from the current declaration")
  func resolvesDynamicCollectionDefaults() throws {
    let scopes = try ScopesSet(["atproto", "space:com.example.forum"])
    let thread = try NSID(string: "com.external.thread")
    let write = SpaceScopeRequirement(
      space: ownSpace, operation: .write(collection: thread, action: .create))

    #expect(!scopes.allowsSpace(write, grantedBy: grantor))
    #expect(
      scopes.allowsSpace(write, grantedBy: grantor, spaceTypes: [ForumSpace.self]))

    let wildcardType = try ScopesSet(["atproto", "space:*?authority=*"])
    #expect(
      !wildcardType.allowsSpace(
        write, grantedBy: grantor, spaceTypes: [ForumSpace.self]))
  }

  @Test("explicit collections and management grants remain independent")
  func separatesWritesAndManagement() throws {
    let collection = try NSID(string: "net.external.thread")
    let scopes = try ScopesSet([
      "atproto",
      "space:com.example.forum?collection=net.external.thread&action=create&manage=delete",
    ])
    let write = SpaceScopeRequirement(
      space: ownSpace, operation: .write(collection: collection, action: .create))
    let updateSpace = SpaceScopeRequirement(space: ownSpace, operation: .manage(.update))
    let deleteSpace = SpaceScopeRequirement(space: ownSpace, operation: .manage(.delete))

    #expect(scopes.allowsSpace(write, grantedBy: grantor))
    #expect(!scopes.allowsSpace(updateSpace, grantedBy: grantor))
    #expect(scopes.allowsSpace(deleteSpace, grantedBy: grantor))
  }

  @Test("transition generic does not grant permissioned space access")
  func doesNotExtendTransitionGeneric() throws {
    let requirement = SpaceScopeRequirement(
      space: ownSpace, operation: .read(repository: grantor))
    let scopes = try ScopesSet(["transition:generic"])

    #expect(!scopes.allowsSpace(requirement, grantedBy: grantor))
    #expect(
      !ScopesSet(rawScopes: ["space:com.example.forum"])
        .allowsSpace(requirement, grantedBy: grantor))
  }

  @Test("space permissions expand with namespace authority checks")
  func expandsPermissionSets() throws {
    let include = try IncludeScope(nsid: "com.example.authForums")
    let permission = LexPermission(
      resource: .space,
      action: [.read, .create],
      collection: ["net.external.thread"],
      spaceType: "com.example.forum",
      authority: "*"
    )

    #expect(
      try include.expand([permission]) == [
        "space:com.example.forum?authority=*&collection=net.external.thread&action=read&action=create"
      ])
    #expect(throws: OAuthScopeError.self) {
      try include.expand([
        LexPermission(resource: .space, spaceType: "net.external.forum")
      ])
    }
    #expect(throws: OAuthScopeError.self) {
      try include.expand([LexPermission(resource: .space, spaceType: "*")])
    }

    let scopes = try ScopesSet(
      ["atproto", "include:com.example.authForums"],
      permissionSets: [ForumPermissions.self])
    #expect(scopes.spaceScopes.count == 1)
  }
}

private enum ForumSpace: LexSpace {
  static let id = "com.example.forum"
  static let key: LexRecordKeyType = .any
  static let name = "Forum"
  static let nameLang: [String: String]? = nil
  static let collections: [FormatString<NSID>] = [
    .init(rawValue: "com.external.thread")
  ]
  static let description: String? = nil
}

private enum ForumPermissions: LexPermissionSet {
  static let id = "com.example.authForums"
  static let title: String? = nil
  static let detail: String? = nil
  static let permissions: [LexPermission] = [
    .init(resource: .space, action: [.read], spaceType: "com.example.forum")
  ]
}
