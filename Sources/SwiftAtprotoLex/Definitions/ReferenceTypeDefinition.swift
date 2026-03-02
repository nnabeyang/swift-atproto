struct ReferenceTypeDefinition: Codable {
  var type: FieldType { .ref }
  let description: String?
  let ref: String

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case ref
  }
}
