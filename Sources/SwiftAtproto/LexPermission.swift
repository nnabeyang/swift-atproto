import Foundation

/// An open value carried by an unrecognized field in a Lexicon permission.
///
/// Permission values are limited to strings, integers, booleans, and arrays of
/// those scalar values. The representation remains open so a client can retain
/// fields introduced by a newer permission resource.
public enum LexPermissionValue: Codable, Hashable, Sendable {
  /// A string value.
  case string(String)
  /// An integer value.
  case integer(Int)
  /// A boolean value.
  case boolean(Bool)
  /// An array whose members must all be scalar permission values.
  case array([LexPermissionValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([LexPermissionValue].self),
      value.allSatisfy(\.isScalar)
    {
      self = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Lexicon permission values must be scalars or arrays of scalars."
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .boolean(let value):
      try container.encode(value)
    case .array(let value):
      guard value.allSatisfy(\.isScalar) else {
        throw EncodingError.invalidValue(
          value,
          .init(
            codingPath: encoder.codingPath,
            debugDescription: "Lexicon permission arrays may only contain scalar values."
          )
        )
      }
      try container.encode(value)
    }
  }

  private var isScalar: Bool {
    if case .array = self { return false }
    return true
  }
}

/// One permission declared by a Lexicon permission set.
///
/// Expanding an ``IncludeScope`` turns these into the structured scope strings
/// they grant. Unrecognized fields are retained in ``additionalFields`` so
/// permission resources introduced by newer Lexicons round-trip losslessly.
public struct LexPermission: Codable, Hashable, Sendable {
  public let resource: LexPermissionResource
  public let aud: String?
  public let inheritAud: Bool?
  public let lxm: [String]?
  public let action: [LexPermissionAction]?
  public let collection: [String]?
  /// The space type selected by a `space` permission.
  public let spaceType: String?
  /// The authority selected by a `space` permission.
  public let authority: String?
  /// The space key selected by a `space` permission.
  public let skey: String?
  /// The space-management operations granted by a `space` permission.
  public let manage: [LexPermissionAction]?
  /// Fields not understood by this version of the library.
  public let additionalFields: [String: LexPermissionValue]

  /// Creates a permission while retaining any resource-specific open fields.
  public init(
    resource: LexPermissionResource,
    aud: String? = nil,
    inheritAud: Bool? = nil,
    lxm: [String]? = nil,
    action: [LexPermissionAction]? = nil,
    collection: [String]? = nil,
    spaceType: String? = nil,
    authority: String? = nil,
    skey: String? = nil,
    manage: [LexPermissionAction]? = nil,
    additionalFields: [String: LexPermissionValue] = [:]
  ) {
    self.resource = resource
    self.aud = aud
    self.inheritAud = inheritAud
    self.lxm = lxm
    self.action = action
    self.collection = collection
    self.spaceType = spaceType
    self.authority = authority
    self.skey = skey
    self.manage = manage
    self.additionalFields = additionalFields.filter { !Self.knownKeys.contains($0.key) }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKeys.self)
    let typeKey = AnyCodingKeys(stringValue: "type")
    guard try container.decode(String.self, forKey: typeKey) == "permission" else {
      throw DecodingError.dataCorruptedError(
        forKey: typeKey,
        in: container,
        debugDescription: "A Lexicon permission must have type 'permission'."
      )
    }
    resource = try container.decode(LexPermissionResource.self, forKey: .init(stringValue: "resource"))
    aud = try container.decodeIfPresent(String.self, forKey: .init(stringValue: "aud"))
    inheritAud = try container.decodeIfPresent(Bool.self, forKey: .init(stringValue: "inheritAud"))
    lxm = try container.decodeIfPresent([String].self, forKey: .init(stringValue: "lxm"))
    action = try container.decodeIfPresent([LexPermissionAction].self, forKey: .init(stringValue: "action"))
    collection = try container.decodeIfPresent([String].self, forKey: .init(stringValue: "collection"))
    spaceType = try container.decodeIfPresent(String.self, forKey: .init(stringValue: "spaceType"))
    authority = try container.decodeIfPresent(String.self, forKey: .init(stringValue: "authority"))
    skey = try container.decodeIfPresent(String.self, forKey: .init(stringValue: "skey"))
    manage = try container.decodeIfPresent([LexPermissionAction].self, forKey: .init(stringValue: "manage"))
    additionalFields = try Dictionary(
      uniqueKeysWithValues: container.allKeys.compactMap { key in
        guard !Self.knownKeys.contains(key.stringValue) else { return nil }
        return (key.stringValue, try container.decode(LexPermissionValue.self, forKey: key))
      })
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AnyCodingKeys.self)
    try container.encode("permission", forKey: .init(stringValue: "type"))
    try container.encode(resource, forKey: .init(stringValue: "resource"))
    try container.encodeIfPresent(aud, forKey: .init(stringValue: "aud"))
    try container.encodeIfPresent(inheritAud, forKey: .init(stringValue: "inheritAud"))
    try container.encodeIfPresent(lxm, forKey: .init(stringValue: "lxm"))
    try container.encodeIfPresent(action, forKey: .init(stringValue: "action"))
    try container.encodeIfPresent(collection, forKey: .init(stringValue: "collection"))
    try container.encodeIfPresent(spaceType, forKey: .init(stringValue: "spaceType"))
    try container.encodeIfPresent(authority, forKey: .init(stringValue: "authority"))
    try container.encodeIfPresent(skey, forKey: .init(stringValue: "skey"))
    try container.encodeIfPresent(manage, forKey: .init(stringValue: "manage"))
    for (key, value) in additionalFields {
      try container.encode(value, forKey: .init(stringValue: key))
    }
  }

  private static let knownKeys: Set<String> = [
    "type", "resource", "aud", "inheritAud", "lxm", "action", "collection",
    "spaceType", "authority", "skey", "manage",
  ]
}

/// The resource kind a ``LexPermission`` applies to.
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
  /// Access to records and management operations within permissioned spaces.
  public static let space = Self(rawValue: "space")
}

/// An action granted by a structured permission resource.
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

  /// Read only the granting account's repository in a space.
  public static let readSelf = Self(rawValue: "read_self")
  /// Read any repository in a space and request a delegation token.
  public static let read = Self(rawValue: "read")
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
