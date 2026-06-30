struct PermissionTypeDefinition: Codable {
  var type: FieldType { .permission }
  let resource: String
  let aud: String?
  let inheritAud: Bool?
  let lxm: [String]?
  let action: [String]?
  let collection: [String]?
}
