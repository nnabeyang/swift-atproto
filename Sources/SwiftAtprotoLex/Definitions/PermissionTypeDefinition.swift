struct PermissionTypeDefinition: Codable {
  var type: FieldType { .permission }
  let resource: PermissionResource
  let aud: String?
  let inheritAud: Bool?
  let lxm: [String]?
  let action: [PermissionAction]?
  let collection: [String]?
}

struct PermissionResource: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: Decoder) throws {
    self.rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let rpc = Self(rawValue: "rpc")
  static let repo = Self(rawValue: "repo")
}

struct PermissionAction: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: Decoder) throws {
    self.rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let create = Self(rawValue: "create")
  static let update = Self(rawValue: "update")
  static let delete = Self(rawValue: "delete")
}
