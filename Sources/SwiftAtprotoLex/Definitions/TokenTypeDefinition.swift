struct TokenTypeDefinition: Codable {
  var type: FieldType { .token }
  let description: String?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
  }
}
