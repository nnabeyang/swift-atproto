struct BooleanTypeDefinition: Codable {
  var type: FieldType { .boolean }
  let description: String?
  let `default`: Bool?
  let const: Bool?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case `default`
    case const
  }
}
