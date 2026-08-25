struct PermissionTypeDefinition: Codable {
  let type: FieldType
  let resource: PermissionResource
  let aud: String?
  let inheritAud: Bool?
  let lxm: [String]?
  let action: [PermissionAction]?
  let collection: [String]?
  let spaceType: String?
  let authority: String?
  let skey: String?
  let manage: [PermissionAction]?
  let additionalFields: [String: PermissionValue]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    type = try container.decode(FieldType.self, forKey: .init("type"))
    resource = try container.decode(PermissionResource.self, forKey: .init("resource"))
    aud = try container.decodeIfPresent(String.self, forKey: .init("aud"))
    inheritAud = try container.decodeIfPresent(Bool.self, forKey: .init("inheritAud"))
    lxm = try container.decodeIfPresent([String].self, forKey: .init("lxm"))
    action = try container.decodeIfPresent([PermissionAction].self, forKey: .init("action"))
    collection = try container.decodeIfPresent([String].self, forKey: .init("collection"))
    spaceType = try container.decodeIfPresent(String.self, forKey: .init("spaceType"))
    authority = try container.decodeIfPresent(String.self, forKey: .init("authority"))
    skey = try container.decodeIfPresent(String.self, forKey: .init("skey"))
    manage = try container.decodeIfPresent([PermissionAction].self, forKey: .init("manage"))
    additionalFields = try Dictionary(
      uniqueKeysWithValues: container.allKeys.compactMap { key in
        guard !Self.knownKeys.contains(key.stringValue) else { return nil }
        return (key.stringValue, try container.decode(PermissionValue.self, forKey: key))
      })
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    try container.encode(type, forKey: .init("type"))
    try container.encode(resource, forKey: .init("resource"))
    try container.encodeIfPresent(aud, forKey: .init("aud"))
    try container.encodeIfPresent(inheritAud, forKey: .init("inheritAud"))
    try container.encodeIfPresent(lxm, forKey: .init("lxm"))
    try container.encodeIfPresent(action, forKey: .init("action"))
    try container.encodeIfPresent(collection, forKey: .init("collection"))
    try container.encodeIfPresent(spaceType, forKey: .init("spaceType"))
    try container.encodeIfPresent(authority, forKey: .init("authority"))
    try container.encodeIfPresent(skey, forKey: .init("skey"))
    try container.encodeIfPresent(manage, forKey: .init("manage"))
    for (key, value) in additionalFields {
      try container.encode(value, forKey: .init(key))
    }
  }

  private static let knownKeys: Set<String> = [
    "type", "resource", "aud", "inheritAud", "lxm", "action", "collection",
    "spaceType", "authority", "skey", "manage",
  ]
}

enum PermissionValue: Codable, Hashable, Sendable {
  case string(String)
  case integer(Int)
  case boolean(Bool)
  case array([PermissionValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([PermissionValue].self),
      value.allSatisfy(\.isScalar)
    {
      self = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Permission values must be scalars or arrays of scalars."
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .boolean(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    }
  }

  private var isScalar: Bool {
    if case .array = self { return false }
    return true
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init(stringValue: String) {
    self.init(stringValue)
  }

  init(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
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
  static let space = Self(rawValue: "space")
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

  static let readSelf = Self(rawValue: "read_self")
  static let read = Self(rawValue: "read")
  static let create = Self(rawValue: "create")
  static let update = Self(rawValue: "update")
  static let delete = Self(rawValue: "delete")
}
