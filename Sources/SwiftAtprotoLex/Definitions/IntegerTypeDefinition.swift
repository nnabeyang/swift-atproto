struct IntegerTypeDefinition: Codable {
  var type: FieldType { .integer }
  let description: String?
  let minimum: Int?
  let maximum: Int?
  let `enum`: [Int]?
  let `default`: Int?
  let const: Int?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case minimum
    case maximum
    case `enum`
    case `default`
    case const
  }

  var isPrimitive: Bool {
    `enum` == nil
  }
}
