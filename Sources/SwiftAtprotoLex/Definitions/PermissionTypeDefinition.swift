struct PermissionTypeDefinition: Codable {
  var type: FieldType { .permission }
  let description: String?
  let resource: String
  let inheritAud: Bool?
  let lxm: [String]?
  let action: [String]?
  let collection: [String]?
}
