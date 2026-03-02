struct BytesTypeDefinition: Codable {
  var type: FieldType { .bytes }
  let minLength: Int?
  let maxLength: Int?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case minLength
    case maxLength
  }
}
