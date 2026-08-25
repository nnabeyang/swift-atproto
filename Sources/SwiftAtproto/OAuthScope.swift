import Foundation

/// The scope strings that are not structured resources.
///
/// Both are broad grants: ``ScopesSet`` treats them as prerequisites for any
/// structured check, and ``transitionGeneric`` satisfies most checks outright.
/// See <doc:OAuthScopes>.
public enum OAuthScope {
  /// The base scope every AT Protocol OAuth session carries.
  public static let atproto = "atproto"
  /// The transitional scope granting broad access, retained for compatibility
  /// with sessions issued before granular scopes.
  public static let transitionGeneric = "transition:generic"
}

/// One repository write a procedure performs, checked against `repo` scope.
public struct RepoWriteRequirement: Hashable, Sendable {
  /// The NSID of the collection being written.
  public let collection: String
  /// The kind of write.
  public let action: LexPermissionAction

  public init(collection: String, action: LexPermissionAction) {
    self.collection = collection
    self.action = action
  }
}

/// A procedure input that declares the repository writes it performs.
///
/// A client with an OAuth session checks these against the granted `repo`
/// scope before sending the request. An input that does not conform is not
/// repo-checked. See <doc:OAuthScopes>.
public protocol RepoWriteOperationDescribing: Sendable {
  /// One requirement per collection and action this operation writes.
  var repoWriteRequirements: [RepoWriteRequirement] { get }
}

/// A scope string that could not be parsed, or a call the granted scopes do
/// not permit.
///
/// The `insufficient*` cases are thrown by the client before a request is sent;
/// the rest come from parsing scopes or expanding an ``IncludeScope``.
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
  case insufficientBlobScope(mime: String)
}

/// An `rpc` scope: permission to call specific methods against a specific
/// audience.
public struct RpcScope: CustomStringConvertible, Hashable, Sendable {
  /// The service this scope applies to, or `*` for any.
  public let aud: String
  /// The method NSIDs this scope permits, or `*` for any.
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

/// A `repo` scope: permission to write specific collections.
public struct RepoScope: CustomStringConvertible, Hashable, Sendable {
  /// The collection NSIDs this scope permits, or `*` for any.
  public let collection: [String]
  /// The write actions this scope permits.
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

/// An operation whose authorization is evaluated against a ``SpaceScope``.
public enum SpaceScopeOperation: Hashable, Sendable {
  /// Read one repository in a space.
  case read(repository: DID)
  /// Request a delegation token for whole-space read access.
  case delegationToken
  /// Write a record in a collection.
  case write(collection: NSID, action: LexPermissionAction)
  /// Perform an implementation-defined space-management operation.
  case manage(LexPermissionAction)
}

/// The target space and operation a consumer wants to authorize.
public struct SpaceScopeRequirement: Hashable, Sendable {
  /// The space being accessed or managed.
  public let space: SpaceRef
  /// The operation being performed.
  public let operation: SpaceScopeOperation

  /// Creates a requirement for one operation against one concrete space.
  public init(space: SpaceRef, operation: SpaceScopeOperation) {
    self.space = space
    self.operation = operation
  }
}

/// A `space` scope granting access to permissioned records and space
/// management operations.
///
/// Collection defaults are intentionally not frozen into this value. Pass the
/// current space declaration to ``ScopesSet/allowsSpace(_:grantedBy:spaceTypes:)``
/// when evaluating a write that relies on its default collections.
public struct SpaceScope: CustomStringConvertible, Hashable, Sendable {
  /// The selected space-type NSID, or `*` for every type.
  public let spaceType: String
  /// The selected authority DID, `self`, or `*`.
  public let authority: String
  /// The selected space key, or `*`.
  public let skey: String
  /// Explicit write collections, or `nil` to use the current space declaration.
  public let collection: [String]?
  /// Granted record actions.
  public let action: [LexPermissionAction]
  /// Granted space-management operations.
  public let manage: [LexPermissionAction]

  /// The actions granted when an `action` parameter is omitted.
  public static let defaultActions: [LexPermissionAction] = [.read, .create, .update, .delete]

  /// Creates and validates a structured space grant.
  ///
  /// Pass `nil` for `collection` to resolve the current ``LexSpace``
  /// declaration when a write is evaluated.
  public init(
    spaceType: String,
    authority: String = "self",
    skey: String = "*",
    collection: [String]? = nil,
    action: [LexPermissionAction] = Self.defaultActions,
    manage: [LexPermissionAction] = []
  ) throws {
    guard spaceType == "*" || NSID.isValid(spaceType) else {
      throw OAuthScopeError.invalidSyntax("invalid spaceType '\(spaceType)' in space scope")
    }
    guard authority == "self" || authority == "*" || (try? DID(string: authority)) != nil else {
      throw OAuthScopeError.invalidSyntax("invalid authority '\(authority)' in space scope")
    }
    guard skey == "*" || RecordKey.isValid(skey) else {
      throw OAuthScopeError.invalidSyntax("invalid skey '\(skey)' in space scope")
    }
    if let collection {
      guard !collection.isEmpty else {
        throw OAuthScopeError.missingRequired("collection")
      }
      for value in collection where value != "*" && !NSID.isValid(value) {
        throw OAuthScopeError.invalidSyntax("invalid collection '\(value)' in space scope")
      }
    }
    guard !action.isEmpty else {
      throw OAuthScopeError.missingRequired("action")
    }
    for value in action where !Self.allowedActions.contains(value) {
      throw OAuthScopeError.invalidSyntax("unknown action '\(value.rawValue)' in space scope")
    }
    for value in manage where !Self.allowedManage.contains(value) {
      throw OAuthScopeError.invalidSyntax("unknown manage operation '\(value.rawValue)' in space scope")
    }

    self.spaceType = spaceType
    self.authority = authority
    self.skey = skey
    self.collection = collection.map(Self.normalizeCollections)
    self.action = Self.normalizeActions(action)
    self.manage = Self.normalizeManage(manage)
  }

  /// Parses a `space:` scope string and applies its protocol defaults.
  public init(string: String) throws {
    let syntax = OAuthScopeSyntax.parse(string)
    guard syntax.prefix == "space" else {
      throw OAuthScopeError.invalidResource(syntax.prefix)
    }
    guard let spaceType = syntax.positional, !spaceType.isEmpty else {
      throw OAuthScopeError.missingRequired("spaceType")
    }

    var authority: String?
    var skey: String?
    var collections: [String] = []
    var actions: [LexPermissionAction] = []
    var management: [LexPermissionAction] = []
    var hasCollection = false
    for parameter in syntax.params {
      guard !parameter.value.isEmpty else {
        throw OAuthScopeError.invalidSyntax("empty \(parameter.key) value in space scope")
      }
      switch parameter.key {
      case "authority":
        guard authority == nil else { throw OAuthScopeError.duplicateKey("authority") }
        authority = parameter.value
      case "skey":
        guard skey == nil else { throw OAuthScopeError.duplicateKey("skey") }
        skey = parameter.value
      case "collection":
        hasCollection = true
        collections.append(parameter.value)
      case "action":
        actions.append(.init(rawValue: parameter.value))
      case "manage":
        management.append(.init(rawValue: parameter.value))
      default:
        throw OAuthScopeError.invalidSyntax("unknown key '\(parameter.key)' in space scope")
      }
    }

    try self.init(
      spaceType: spaceType,
      authority: authority ?? "self",
      skey: skey ?? "*",
      collection: hasCollection ? collections : nil,
      action: actions.isEmpty ? Self.defaultActions : actions,
      manage: management
    )
  }

  public var description: String {
    var parameters: [OAuthScopeQueryParam] = []
    if authority != "self" {
      parameters.append(.init(key: "authority", value: authority))
    }
    if skey != "*" {
      parameters.append(.init(key: "skey", value: skey))
    }
    if let collection {
      parameters.append(contentsOf: collection.map { .init(key: "collection", value: $0) })
    }
    if action != Self.defaultActions {
      parameters.append(contentsOf: action.map { .init(key: "action", value: $0.rawValue) })
    }
    parameters.append(contentsOf: manage.map { .init(key: "manage", value: $0.rawValue) })
    return OAuthScopeSyntax(prefix: "space", positional: spaceType, params: parameters).description
  }

  fileprivate func allows(
    _ requirement: SpaceScopeRequirement,
    grantedBy: DID,
    spaceTypes: [any LexSpace.Type]
  ) -> Bool {
    let space = requirement.space
    guard spaceType == "*" || spaceType == space.spaceType.rawValue else { return false }
    guard skey == "*" || skey == space.skey.rawValue else { return false }
    switch authority {
    case "*":
      break
    case "self":
      guard space.spaceDid == grantedBy else { return false }
    default:
      guard authority == space.spaceDid.rawValue else { return false }
    }

    switch requirement.operation {
    case .read(let repository):
      return action.contains(.read) || (action.contains(.readSelf) && repository == grantedBy)
    case .delegationToken:
      return action.contains(.read)
    case .write(let requiredCollection, let requiredAction):
      guard Self.allowedManage.contains(requiredAction), action.contains(requiredAction) else {
        return false
      }
      return effectiveCollections(for: space, spaceTypes: spaceTypes).contains {
        $0 == "*" || $0 == requiredCollection.rawValue
      }
    case .manage(let requiredOperation):
      return Self.allowedManage.contains(requiredOperation) && manage.contains(requiredOperation)
    }
  }

  private func effectiveCollections(
    for space: SpaceRef,
    spaceTypes: [any LexSpace.Type]
  ) -> [String] {
    if let collection { return collection }
    guard spaceType != "*",
      let declaration = spaceTypes.first(where: { $0.id == space.spaceType.rawValue })
    else {
      return []
    }
    return declaration.collections.map(\.rawValue)
  }

  private static let allowedActions: [LexPermissionAction] = [
    .readSelf, .read, .create, .update, .delete,
  ]
  private static let allowedManage: [LexPermissionAction] = [.create, .update, .delete]

  private static func normalizeCollections(_ values: [String]) -> [String] {
    if values.contains("*") { return ["*"] }
    return Array(Set(values)).sorted()
  }

  private static func normalizeActions(_ values: [LexPermissionAction]) -> [LexPermissionAction] {
    var seen = Set(values)
    if seen.contains(.read) { seen.remove(.readSelf) }
    return allowedActions.filter { seen.contains($0) }
  }

  private static func normalizeManage(_ values: [LexPermissionAction]) -> [LexPermissionAction] {
    let seen = Set(values)
    return allowedManage.filter { seen.contains($0) }
  }
}

/// A `blob` scope: permission to upload specific MIME types.
public struct BlobScope: CustomStringConvertible, Hashable, Sendable {
  /// The accepted MIME patterns, which may use a `*` subtype such as
  /// `image/*`.
  public let accept: [String]

  public init(accept: [String]) throws {
    guard !accept.isEmpty else {
      throw OAuthScopeError.missingRequired("accept")
    }
    for value in accept where !Self.isValidAccept(value) {
      throw OAuthScopeError.invalidSyntax("invalid accept '\(value)' in blob scope")
    }
    self.accept = Self.normalize(accept: accept)
  }

  public init(string: String) throws {
    let syntax = OAuthScopeSyntax.parse(string)
    guard syntax.prefix == "blob" else {
      throw OAuthScopeError.invalidResource(syntax.prefix)
    }
    var accepts: [String] = []
    var sawAcceptInQuery = false
    if let positional = syntax.positional {
      guard !positional.isEmpty else {
        throw OAuthScopeError.invalidSyntax("empty positional in blob scope")
      }
      accepts.append(positional)
    }
    for param in syntax.params {
      switch param.key {
      case "accept":
        sawAcceptInQuery = true
        guard !param.value.isEmpty else {
          throw OAuthScopeError.invalidSyntax("empty accept value in blob scope")
        }
        accepts.append(param.value)
      default:
        throw OAuthScopeError.invalidSyntax("unknown key '\(param.key)' in blob scope")
      }
    }
    if syntax.positional != nil, sawAcceptInQuery {
      throw OAuthScopeError.invalidSyntax("blob scope has both positional and accept query")
    }
    try self.init(accept: accepts)
  }

  public var description: String {
    if accept.count == 1 {
      return OAuthScopeSyntax(prefix: "blob", positional: accept[0]).description
    }
    let params = accept.map { OAuthScopeQueryParam(key: "accept", value: $0) }
    return OAuthScopeSyntax(prefix: "blob", params: params).description
  }

  /// Whether this scope accepts the given MIME type.
  public func allows(mime: String) -> Bool {
    guard Self.isValidMime(mime) else {
      return false
    }
    let normalizedMime = mime.lowercased()
    for value in accept {
      if value == "*/*" {
        return true
      }
      if value.hasSuffix("/*") {
        let prefix = String(value.dropLast())
        if normalizedMime.hasPrefix(prefix) {
          return true
        }
      } else if value == normalizedMime {
        return true
      }
    }
    return false
  }

  private static func normalize(accept: [String]) -> [String] {
    var normalized = Array(Set(accept.map { $0.lowercased() })).sorted()
    if normalized.contains("*/*") {
      return ["*/*"]
    }
    let wildcards = Set(normalized.filter { $0.hasSuffix("/*") }.map { String($0.split(separator: "/", maxSplits: 1)[0]) })
    normalized.removeAll { value in
      guard !value.hasSuffix("/*") else { return false }
      let type = String(value.split(separator: "/", maxSplits: 1)[0])
      return wildcards.contains(type)
    }
    return normalized
  }

  private static func isValidAccept(_ value: String) -> Bool {
    if value == "*/*" {
      return true
    }
    guard isValidMimeLike(value) else {
      return false
    }
    if value.contains("*") {
      return value.hasSuffix("/*") && value.dropLast(2).allSatisfy { $0 != "*" }
    }
    return true
  }

  private static func isValidMime(_ value: String) -> Bool {
    isValidMimeLike(value) && !value.contains("*")
  }

  private static func isValidMimeLike(_ value: String) -> Bool {
    let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard
      parts.count == 2,
      !parts[0].isEmpty,
      !parts[1].isEmpty,
      value.allSatisfy({ $0.isPrintableNonWhitespaceASCII }),
      !value.contains(" ")
    else {
      return false
    }
    return true
  }
}

/// An `include` scope: a reference to a permission set rather than a list of
/// permissions.
///
/// ``ScopesSet`` expands each include at construction, adding the resulting
/// `rpc`, `repo`, and `space` scopes. An include may only grant permissions under its own
/// authority. See <doc:OAuthScopes>.
public struct IncludeScope: CustomStringConvertible, Hashable, Sendable {
  /// The NSID of the permission set being included.
  public let nsid: String
  /// The audience the expanded permissions apply to, when the include pins one.
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

  /// Whether `otherNsid` falls under this include's namespace authority.
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

  /// Expands a permission set type into the scope strings it grants.
  ///
  /// - Throws: ``OAuthScopeError/nsidOutsideAuthority(parent:other:)`` when a
  ///   permission names an NSID outside this include's authority.
  public func expand<PS: LexPermissionSet>(_ permissionSet: PS.Type) throws -> [String] {
    guard PS.id == nsid else {
      throw OAuthScopeError.invalidSyntax(
        "permission-set id '\(PS.id)' does not match include scope nsid '\(nsid)'")
    }
    return try expand(permissionSet.permissions)
  }

  /// Expands permissions into the scope strings they grant.
  public func expand(_ permissions: [LexPermission]) throws -> [String] {
    var scopes: [String] = []
    for permission in permissions {
      switch permission.resource {
      case .rpc:
        scopes.append(try expandRpc(permission))
      case .repo:
        scopes.append(try expandRepo(permission))
      case .space:
        scopes.append(try expandSpace(permission))
      default:
        continue
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

  private func expandSpace(_ permission: LexPermission) throws -> String {
    guard let spaceType = permission.spaceType else {
      throw OAuthScopeError.missingRequired("spaceType in space permission")
    }
    guard spaceType != "*" else {
      throw OAuthScopeError.forbiddenCombination(
        "space permission in a permission-set cannot use spaceType=*"
      )
    }
    guard isParentAuthorityOf(spaceType) else {
      throw OAuthScopeError.nsidOutsideAuthority(parent: nsid, other: spaceType)
    }
    return try SpaceScope(
      spaceType: spaceType,
      authority: permission.authority ?? "self",
      skey: permission.skey ?? "*",
      collection: permission.collection,
      action: permission.action ?? SpaceScope.defaultActions,
      manage: permission.manage ?? []
    ).description
  }
}

/// The scopes granted to an OAuth session, parsed into structured resources.
///
/// Constructing this expands every ``IncludeScope`` against the permission sets
/// passed in. See <doc:OAuthScopes>.
public struct ScopesSet: Hashable, Sendable {
  /// The granted `rpc` scopes, including those from expanded includes.
  public let rpcScopes: [RpcScope]
  /// The granted `repo` scopes, including those from expanded includes.
  public let repoScopes: [RepoScope]
  /// The granted `blob` scopes.
  public let blobScopes: [BlobScope]
  /// The granted `space` scopes, including those from expanded includes.
  public let spaceScopes: [SpaceScope]
  /// The `include` scopes as written, before expansion.
  public let includeScopes: [IncludeScope]
  /// Granted scopes that are not structured resources, such as
  /// ``OAuthScope/atproto``.
  public let rawOther: Set<String>

  /// Parses granted scopes, rejecting any that are malformed.
  ///
  /// Use this to validate scopes you control. For a token issued by a server
  /// that may use scopes this library does not know, use
  /// ``init(rawScopes:permissionSets:)``.
  public init(_ scopes: [String], permissionSets: [any LexPermissionSet.Type] = []) throws {
    var rpc: [RpcScope] = []
    var repo: [RepoScope] = []
    var blob: [BlobScope] = []
    var space: [SpaceScope] = []
    var include: [IncludeScope] = []
    var other: Set<String> = []
    for scope in scopes {
      let syntax = OAuthScopeSyntax.parse(scope)
      switch syntax.prefix {
      case "rpc":
        rpc.append(try RpcScope(string: scope))
      case "repo":
        repo.append(try RepoScope(string: scope))
      case "blob":
        blob.append(try BlobScope(string: scope))
      case "space":
        space.append(try SpaceScope(string: scope))
      case "include":
        include.append(try IncludeScope(string: scope))
      default:
        guard isValidRawOAuthScope(scope) else {
          throw OAuthScopeError.invalidSyntax("invalid scope '\(scope)'")
        }
        other.insert(scope)
      }
    }
    try Self.expandIncludes(
      include, permissionSets: permissionSets, into: &rpc, repo: &repo, space: &space)
    self.rpcScopes = rpc
    self.repoScopes = repo
    self.blobScopes = blob
    self.spaceScopes = space
    self.includeScopes = include
    self.rawOther = other
  }

  /// Parses granted scopes, silently dropping any that cannot be parsed.
  public init(rawScopes scopes: [String], permissionSets: [any LexPermissionSet.Type] = []) {
    var rpc: [RpcScope] = []
    var repo: [RepoScope] = []
    var blob: [BlobScope] = []
    var space: [SpaceScope] = []
    var include: [IncludeScope] = []
    var other: Set<String> = []
    for scope in scopes {
      let syntax = OAuthScopeSyntax.parse(scope)
      switch syntax.prefix {
      case "rpc":
        if let parsed = try? RpcScope(string: scope) { rpc.append(parsed) }
      case "repo":
        if let parsed = try? RepoScope(string: scope) { repo.append(parsed) }
      case "blob":
        if let parsed = try? BlobScope(string: scope) { blob.append(parsed) }
      case "space":
        if let parsed = try? SpaceScope(string: scope) { space.append(parsed) }
      case "include":
        if let parsed = try? IncludeScope(string: scope) { include.append(parsed) }
      default:
        guard isValidRawOAuthScope(scope) else {
          continue
        }
        other.insert(scope)
      }
    }
    try? Self.expandIncludes(
      include, permissionSets: permissionSets, into: &rpc, repo: &repo, space: &space)
    self.rpcScopes = rpc
    self.repoScopes = repo
    self.blobScopes = blob
    self.spaceScopes = space
    self.includeScopes = include
    self.rawOther = other
  }

  private static func expandIncludes(
    _ includes: [IncludeScope],
    permissionSets: [any LexPermissionSet.Type],
    into rpc: inout [RpcScope],
    repo: inout [RepoScope],
    space: inout [SpaceScope]
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
        case "space":
          space.append(try SpaceScope(string: scopeStr))
        default:
          break
        }
      }
    }
  }

  /// Whether the base ``OAuthScope/atproto`` scope was granted, which every
  /// structured check requires.
  public var hasAtprotoScope: Bool {
    rawOther.contains(OAuthScope.atproto)
  }

  /// Whether the broad ``OAuthScope/transitionGeneric`` scope was granted.
  public var hasTransitionGeneric: Bool {
    rawOther.contains(OAuthScope.transitionGeneric)
  }

  /// Whether this session may call `lxm` against the service `aud`.
  public func allowsRpc(lxm: String, aud: String) -> Bool {
    guard hasAtprotoScope || hasTransitionGeneric else {
      return false
    }
    if hasTransitionGeneric, lxm != "*", !lxm.hasPrefix("chat.bsky.") {
      return true
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

  /// Whether this session may perform `action` on `collection`.
  public func allowsRepo(collection: String, action: LexPermissionAction) -> Bool {
    guard hasAtprotoScope || hasTransitionGeneric else {
      return false
    }
    if hasTransitionGeneric {
      return true
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

  /// Whether this session may upload a blob of type `mime`.
  public func allowsBlob(mime: String) -> Bool {
    guard hasAtprotoScope || hasTransitionGeneric else {
      return false
    }
    if hasTransitionGeneric {
      return true
    }
    for scope in blobScopes where scope.allows(mime: mime) {
      return true
    }
    return false
  }

  /// Whether this session's OAuth scopes satisfy a permissioned-space
  /// requirement.
  ///
  /// `grantedBy` resolves `authority=self` and identifies the repository that
  /// a `read_self` grant may read. `spaceTypes` is consulted at evaluation time
  /// when a scope omits `collection`, so declaration updates are not frozen
  /// into the granted scope.
  public func allowsSpace(
    _ requirement: SpaceScopeRequirement,
    grantedBy: DID,
    spaceTypes: [any LexSpace.Type] = []
  ) -> Bool {
    guard hasAtprotoScope else { return false }
    return spaceScopes.contains {
      $0.allows(requirement, grantedBy: grantedBy, spaceTypes: spaceTypes)
    }
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
