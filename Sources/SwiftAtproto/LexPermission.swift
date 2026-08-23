import Foundation

/// One permission declared by a Lexicon permission set.
///
/// Expanding an ``IncludeScope`` turns these into the `rpc` and `repo` scope
/// strings they grant. See <doc:OAuthScopes>.
public struct LexPermission: Codable, Hashable, Sendable {
  public let resource: LexPermissionResource
  public let aud: String?
  public let inheritAud: Bool?
  public let lxm: [String]?
  public let action: [LexPermissionAction]?
  public let collection: [String]?

  public init(
    resource: LexPermissionResource,
    aud: String? = nil,
    inheritAud: Bool? = nil,
    lxm: [String]? = nil,
    action: [LexPermissionAction]? = nil,
    collection: [String]? = nil
  ) {
    self.resource = resource
    self.aud = aud
    self.inheritAud = inheritAud
    self.lxm = lxm
    self.action = action
    self.collection = collection
  }
}

/// The resource kind a ``LexPermission`` applies to: `rpc`, `repo`, or `blob`.
public struct LexPermissionResource: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    self.rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let rpc = Self(rawValue: "rpc")
  public static let repo = Self(rawValue: "repo")
  public static let blob = Self(rawValue: "blob")
}

/// A repository write action: `create`, `update`, or `delete`.
public struct LexPermissionAction: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    self.rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let create = Self(rawValue: "create")
  public static let update = Self(rawValue: "update")
  public static let delete = Self(rawValue: "delete")
}

/// A named set of permissions, generated from a Lexicon `permission-set`.
///
/// Pass conforming types to ``ScopesSet/init(_:permissionSets:)`` so an
/// ``IncludeScope`` naming ``id`` can be expanded. See <doc:OAuthScopes>.
public protocol LexPermissionSet {
  /// The NSID an ``IncludeScope`` refers to this set by.
  static var id: String { get }
  /// A short human-readable name, for a consent screen.
  static var title: String? { get }
  /// A longer human-readable description, for a consent screen.
  static var detail: String? { get }
  /// The permissions this set grants.
  static var permissions: [LexPermission] { get }
}
