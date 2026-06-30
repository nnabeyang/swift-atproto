import Foundation

public enum OAuthScope {
  public static let atproto = "atproto"
}

public enum OAuthScopeError: Error, Hashable, Sendable {
  case invalidSyntax(String)
  case invalidResource(String)
  case duplicateKey(String)
  case missingRequired(String)
  case forbiddenCombination(String)
  case permissionAudMismatch(String)
  case nsidOutsideAuthority(parent: String, other: String)
  case unsupportedResource(String)
}

public struct RpcScope: CustomStringConvertible, Hashable, Sendable {
  public let aud: String
  public let lxm: [String]

  public init(aud: String, lxm: [String]) throws {
    guard !lxm.isEmpty else {
      throw OAuthScopeError.missingRequired("lxm")
    }
    let normalized = Self.normalize(lxm: lxm)
    if aud == "*", normalized.contains("*") {
      throw OAuthScopeError.forbiddenCombination("rpc:* with aud:*")
    }
    self.aud = aud
    self.lxm = normalized
  }

  public init(string: String) throws {
    let syntax = OAuthScopeSyntax.parse(string)
    guard syntax.prefix == "rpc" else {
      throw OAuthScopeError.invalidResource(syntax.prefix)
    }
    var lxms: [String] = []
    var aud: String? = nil
    var sawLxmInQuery = false
    if let positional = syntax.positional {
      guard !positional.isEmpty else {
        throw OAuthScopeError.invalidSyntax("empty positional in rpc scope")
      }
      lxms.append(positional)
    }
    for param in syntax.params {
      switch param.key {
      case "lxm":
        sawLxmInQuery = true
        guard !param.value.isEmpty else {
          throw OAuthScopeError.invalidSyntax("empty lxm value in rpc scope")
        }
        lxms.append(param.value)
      case "aud":
        if aud != nil {
          throw OAuthScopeError.duplicateKey("aud")
        }
        aud = param.value
      default:
        throw OAuthScopeError.invalidSyntax("unknown key '\(param.key)' in rpc scope")
      }
    }
    if syntax.positional != nil, sawLxmInQuery {
      throw OAuthScopeError.invalidSyntax("rpc scope has both positional and lxm query")
    }
    guard let audValue = aud, !audValue.isEmpty else {
      throw OAuthScopeError.missingRequired("aud")
    }
    try self.init(aud: audValue, lxm: lxms)
  }

  public var description: String {
    var params: [OAuthScopeQueryParam] = []
    var positional: String? = nil
    if lxm.count == 1 {
      positional = lxm[0]
    } else {
      for value in lxm {
        params.append(OAuthScopeQueryParam(key: "lxm", value: value))
      }
    }
    params.append(OAuthScopeQueryParam(key: "aud", value: aud))
    return OAuthScopeSyntax(prefix: "rpc", positional: positional, params: params).description
  }

  private static func normalize(lxm: [String]) -> [String] {
    if lxm.count > 1, lxm.contains("*") {
      return ["*"]
    }
    return Array(Set(lxm)).sorted()
  }
}

public struct RepoScope: CustomStringConvertible, Hashable, Sendable {
  public let collection: [String]
  public let action: [LexPermissionAction]

  public static let defaultActions: [LexPermissionAction] = [.create, .update, .delete]

  public init(collection: [String], action: [LexPermissionAction] = Self.defaultActions) throws {
    guard !collection.isEmpty else {
      throw OAuthScopeError.missingRequired("collection")
    }
    guard !action.isEmpty else {
      throw OAuthScopeError.missingRequired("action")
    }
    for a in action where !Self.defaultActions.contains(a) {
      throw OAuthScopeError.invalidSyntax("unknown action '\(a.rawValue)' in repo scope")
    }
    self.collection = Self.normalize(collection: collection)
    self.action = Self.normalize(action: action)
  }

  public init(string: String) throws {
    let syntax = OAuthScopeSyntax.parse(string)
    guard syntax.prefix == "repo" else {
      throw OAuthScopeError.invalidResource(syntax.prefix)
    }
    var collections: [String] = []
    var actions: [LexPermissionAction] = []
    var sawCollectionInQuery = false
    if let positional = syntax.positional {
      guard !positional.isEmpty else {
        throw OAuthScopeError.invalidSyntax("empty positional in repo scope")
      }
      collections.append(positional)
    }
    for param in syntax.params {
      switch param.key {
      case "collection":
        sawCollectionInQuery = true
        guard !param.value.isEmpty else {
          throw OAuthScopeError.invalidSyntax("empty collection value in repo scope")
        }
        collections.append(param.value)
      case "action":
        guard !param.value.isEmpty else {
          throw OAuthScopeError.invalidSyntax("empty action value in repo scope")
        }
        actions.append(LexPermissionAction(rawValue: param.value))
      default:
        throw OAuthScopeError.invalidSyntax("unknown key '\(param.key)' in repo scope")
      }
    }
    if syntax.positional != nil, sawCollectionInQuery {
      throw OAuthScopeError.invalidSyntax("repo scope has both positional and collection query")
    }
    guard !collections.isEmpty else {
      throw OAuthScopeError.missingRequired("collection")
    }
    let effectiveActions = actions.isEmpty ? Self.defaultActions : actions
    try self.init(collection: collections, action: effectiveActions)
  }

  public var description: String {
    var params: [OAuthScopeQueryParam] = []
    var positional: String? = nil
    if collection.count == 1 {
      positional = collection[0]
    } else {
      for value in collection {
        params.append(OAuthScopeQueryParam(key: "collection", value: value))
      }
    }
    if action != Self.defaultActions {
      for a in action {
        params.append(OAuthScopeQueryParam(key: "action", value: a.rawValue))
      }
    }
    return OAuthScopeSyntax(prefix: "repo", positional: positional, params: params).description
  }

  private static func normalize(collection: [String]) -> [String] {
    guard collection.count > 1 else { return collection }
    if collection.contains("*") { return ["*"] }
    return Array(Set(collection)).sorted()
  }

  private static func normalize(action: [LexPermissionAction]) -> [LexPermissionAction] {
    let seen = Set(action)
    return Self.defaultActions.filter { seen.contains($0) }
  }
}
