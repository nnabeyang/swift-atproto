struct PermissionSetTypeDefinition: Codable {
  let type: FieldType
  let description: String?
  let title: String?
  let titleLang: [String: String]?
  let detail: String?
  let detailLang: [String: String]?
  let permissions: [PermissionTypeDefinition]

  private enum CodingKeys: String, CodingKey {
    case type
    case description
    case title
    case titleLang = "title:lang"
    case detail
    case detailLang = "detail:lang"
    case permissions
  }
}
