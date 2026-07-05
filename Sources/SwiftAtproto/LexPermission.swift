import Foundation

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

public protocol LexPermissionSet {
  static var id: String { get }
  static var title: String? { get }
  static var detail: String? { get }
  static var permissions: [LexPermission] { get }
}
