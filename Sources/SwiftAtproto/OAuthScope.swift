import Foundation

public enum OAuthScope {
  public static let atproto = "atproto"
}

public struct RepoWriteRequirement: Hashable, Sendable {
  public let collection: String
  public let action: LexPermissionAction

  public init(collection: String, action: LexPermissionAction) {
    self.collection = collection
    self.action = action
  }
}

public protocol RepoWriteOperationDescribing: Sendable {
  var repoWriteRequirements: [RepoWriteRequirement] { get }
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
  case insufficientScope(lxm: String, aud: String)
  case insufficientRepoScope(collection: String, action: LexPermissionAction)
}

public struct RpcScope: CustomStringConvertible, Hashable, Sendable {
  public let aud: String
  public let lxm: [String]

  public init(aud: String, lxm: [String]) throws {
    guard !lxm.isEmpty else {
      throw OAuthScopeError.missingRequired("lxm")
    }
    guard Self.isValidAudience(aud) else {
      throw OAuthScopeError.invalidSyntax("invalid aud '\(aud)' in rpc scope")
    }
    for value in lxm where !Self.isValidLxm(value) {
      throw OAuthScopeError.invalidSyntax("invalid lxm '\(value)' in rpc scope")
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

  private static func isValidLxm(_ value: String) -> Bool {
    value == "*" || NSID.isValid(value)
  }

  private static func isValidAudience(_ value: String) -> Bool {
    isValidOAuthAudience(value)
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
    for value in collection where !Self.isValidCollection(value) {
      throw OAuthScopeError.invalidSyntax("invalid collection '\(value)' in repo scope")
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

  private static func isValidCollection(_ value: String) -> Bool {
    value == "*" || NSID.isValid(value)
  }
}

public struct IncludeScope: CustomStringConvertible, Hashable, Sendable {
  public let nsid: String
  public let aud: String?

  public init(nsid: String, aud: String? = nil) throws {
    guard NSID.isValid(nsid) else {
      throw OAuthScopeError.invalidSyntax("invalid NSID '\(nsid)' in include scope")
    }
    if let aud, !isValidOAuthAudience(aud) {
      throw OAuthScopeError.invalidSyntax("invalid aud '\(aud)' in include scope")
    }
    self.nsid = nsid
    self.aud = aud
  }

  public init(string: String) throws {
    let syntax = OAuthScopeSyntax.parse(string)
    guard syntax.prefix == "include" else {
      throw OAuthScopeError.invalidResource(syntax.prefix)
    }
    if let positional = syntax.positional, positional.isEmpty {
      throw OAuthScopeError.invalidSyntax("empty positional in include scope")
    }
    var nsid: String? = syntax.positional
    var aud: String? = nil
    var sawNsidInQuery = false
    for param in syntax.params {
      switch param.key {
      case "nsid":
        sawNsidInQuery = true
        if nsid != nil {
          throw OAuthScopeError.duplicateKey("nsid")
        }
        nsid = param.value
      case "aud":
        if aud != nil {
          throw OAuthScopeError.duplicateKey("aud")
        }
        guard !param.value.isEmpty else {
          throw OAuthScopeError.invalidSyntax("empty aud value in include scope")
        }
        aud = param.value
      default:
        throw OAuthScopeError.invalidSyntax("unknown key '\(param.key)' in include scope")
      }
    }
    if syntax.positional != nil, sawNsidInQuery {
      throw OAuthScopeError.invalidSyntax("include scope has both positional and nsid query")
    }
    guard let nsidValue = nsid else {
      throw OAuthScopeError.missingRequired("nsid")
    }
    try self.init(nsid: nsidValue, aud: aud)
  }

  public var description: String {
    var params: [OAuthScopeQueryParam] = []
    if let aud {
      params.append(OAuthScopeQueryParam(key: "aud", value: aud))
    }
    return OAuthScopeSyntax(prefix: "include", positional: nsid, params: params).description
  }

  public func isParentAuthorityOf(_ otherNsid: String) -> Bool {
    if otherNsid == "*" { return false }
    guard let groupPrefixEnd = nsid.lastIndex(of: ".") else {
      return false
    }
    let groupPrefixEndOffset = nsid.distance(from: nsid.startIndex, to: groupPrefixEnd)
    let otherLength = otherNsid.utf8.count
    if groupPrefixEndOffset >= otherLength - 1 {
      return false
    }
    let nsidBytes = Array(nsid.utf8)
    let otherBytes = Array(otherNsid.utf8)
    for i in 0...groupPrefixEndOffset where nsidBytes[i] != otherBytes[i] {
      return false
    }
    return true
  }

  public func expand<PS: LexPermissionSet>(_ permissionSet: PS.Type) throws -> [String] {
    guard PS.id == nsid else {
      throw OAuthScopeError.invalidSyntax(
        "permission-set id '\(PS.id)' does not match include scope nsid '\(nsid)'")
    }
    return try expand(permissionSet.permissions)
  }

  public func expand(_ permissions: [LexPermission]) throws -> [String] {
    var scopes: [String] = []
    for permission in permissions {
      switch permission.resource {
      case .rpc:
        scopes.append(try expandRpc(permission))
      case .repo:
        scopes.append(try expandRepo(permission))
      default:
        throw OAuthScopeError.unsupportedResource(permission.resource.rawValue)
      }
    }
    return scopes
  }

  private func expandRpc(_ permission: LexPermission) throws -> String {
    let resolvedAud: String
    if let permAud = permission.aud {
      if permAud != "*" {
        throw OAuthScopeError.permissionAudMismatch(
          "rpc permission has specific aud '\(permAud)' which is not allowed in permission-set")
      }
      resolvedAud = "*"
    } else if permission.inheritAud == true {
      guard let includeAud = aud else {
        throw OAuthScopeError.permissionAudMismatch(
          "rpc permission has inheritAud=true but include scope has no aud")
      }
      resolvedAud = includeAud
    } else {
      throw OAuthScopeError.missingRequired(
        "rpc permission has neither aud nor inheritAud=true")
    }

    guard let lxm = permission.lxm, !lxm.isEmpty else {
      throw OAuthScopeError.missingRequired("lxm in rpc permission")
    }
    for nsidValue in lxm where !isParentAuthorityOf(nsidValue) {
      throw OAuthScopeError.nsidOutsideAuthority(parent: nsid, other: nsidValue)
    }
    return try RpcScope(aud: resolvedAud, lxm: lxm).description
  }

  private func expandRepo(_ permission: LexPermission) throws -> String {
    guard let collection = permission.collection, !collection.isEmpty else {
      throw OAuthScopeError.missingRequired("collection in repo permission")
    }
    for nsidValue in collection where !isParentAuthorityOf(nsidValue) {
      throw OAuthScopeError.nsidOutsideAuthority(parent: nsid, other: nsidValue)
    }
    let actions = permission.action ?? RepoScope.defaultActions
    return try RepoScope(collection: collection, action: actions).description
  }
}

public struct ScopesSet: Hashable, Sendable {
  public let rpcScopes: [RpcScope]
  public let repoScopes: [RepoScope]
  public let includeScopes: [IncludeScope]
  public let rawOther: Set<String>

  public init(_ scopes: [String], permissionSets: [any LexPermissionSet.Type] = []) throws {
    var rpc: [RpcScope] = []
    var repo: [RepoScope] = []
    var include: [IncludeScope] = []
    var other: Set<String> = []
    for scope in scopes {
      let syntax = OAuthScopeSyntax.parse(scope)
      switch syntax.prefix {
      case "rpc":
        rpc.append(try RpcScope(string: scope))
      case "repo":
        repo.append(try RepoScope(string: scope))
      case "include":
        include.append(try IncludeScope(string: scope))
      default:
        guard isValidRawOAuthScope(scope) else {
          throw OAuthScopeError.invalidSyntax("invalid scope '\(scope)'")
        }
        other.insert(scope)
      }
    }
    try Self.expandIncludes(include, permissionSets: permissionSets, into: &rpc, repo: &repo)
    self.rpcScopes = rpc
    self.repoScopes = repo
    self.includeScopes = include
    self.rawOther = other
  }

  public init(rawScopes scopes: [String], permissionSets: [any LexPermissionSet.Type] = []) {
    var rpc: [RpcScope] = []
    var repo: [RepoScope] = []
    var include: [IncludeScope] = []
    var other: Set<String> = []
    for scope in scopes {
      let syntax = OAuthScopeSyntax.parse(scope)
      switch syntax.prefix {
      case "rpc":
        if let parsed = try? RpcScope(string: scope) { rpc.append(parsed) }
      case "repo":
        if let parsed = try? RepoScope(string: scope) { repo.append(parsed) }
      case "include":
        if let parsed = try? IncludeScope(string: scope) { include.append(parsed) }
      default:
        guard isValidRawOAuthScope(scope) else {
          continue
        }
        other.insert(scope)
      }
    }
    try? Self.expandIncludes(include, permissionSets: permissionSets, into: &rpc, repo: &repo)
    self.rpcScopes = rpc
    self.repoScopes = repo
    self.includeScopes = include
    self.rawOther = other
  }

  private static func expandIncludes(
    _ includes: [IncludeScope],
    permissionSets: [any LexPermissionSet.Type],
    into rpc: inout [RpcScope],
    repo: inout [RepoScope]
  ) throws {
    guard !permissionSets.isEmpty, !includes.isEmpty else { return }
    let registry = Dictionary(
      permissionSets.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for include in includes {
      guard let psType = registry[include.nsid] else { continue }
      let expanded = try include.expand(psType)
      for scopeStr in expanded {
        let syntax = OAuthScopeSyntax.parse(scopeStr)
        switch syntax.prefix {
        case "rpc":
          rpc.append(try RpcScope(string: scopeStr))
        case "repo":
          repo.append(try RepoScope(string: scopeStr))
        default:
          break
        }
      }
    }
  }

  public var hasAtprotoScope: Bool {
    rawOther.contains(OAuthScope.atproto)
  }

  public func allowsRpc(lxm: String, aud: String) -> Bool {
    guard hasAtprotoScope else {
      return false
    }
    for scope in rpcScopes {
      let lxmMatches = scope.lxm.contains(lxm) || scope.lxm.contains("*")
      let audMatches = scope.aud == aud || scope.aud == "*"
      if lxmMatches, audMatches {
        return true
      }
    }
    return false
  }

  public func allowsRepo(collection: String, action: LexPermissionAction) -> Bool {
    guard hasAtprotoScope else {
      return false
    }
    for scope in repoScopes {
      let collMatches = scope.collection.contains(collection) || scope.collection.contains("*")
      let actionMatches = scope.action.contains(action)
      if collMatches, actionMatches {
        return true
      }
    }
    return false
  }
}

private func isValidOAuthAudience(_ value: String) -> Bool {
  if value == "*" {
    return true
  }
  guard
    let fragmentStart = value.firstIndex(of: "#"),
    fragmentStart > value.startIndex,
    value.index(after: fragmentStart) < value.endIndex,
    value[value.index(after: fragmentStart)...].allSatisfy({ $0.isPrintableNonWhitespaceASCII })
  else {
    return false
  }
  let didPart = String(value[..<fragmentStart])
  return (try? DID(string: didPart)) != nil
}

private func isValidRawOAuthScope(_ scope: String) -> Bool {
  guard !scope.isEmpty else {
    return false
  }
  return scope.allSatisfy(\.isPrintableNonWhitespaceASCII)
}

extension Character {
  fileprivate var isPrintableNonWhitespaceASCII: Bool {
    unicodeScalars.count == 1
      && unicodeScalars.allSatisfy { scalar in
        scalar.value >= 0x21 && scalar.value <= 0x7E
      }
  }
}
