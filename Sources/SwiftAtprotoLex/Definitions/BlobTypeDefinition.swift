struct BlobTypeDefinition: Codable {
  var type: FieldType { .blob }
  let accept: [String]?
  let maxSize: Int?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case accept
    case maxSize
  }
}
