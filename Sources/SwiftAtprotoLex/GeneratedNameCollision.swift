import Foundation

/// A Lexicon field whose name a generated type also uses for a declaration of
/// its own, which Swift would reject as a redeclaration.
///
/// The Lexicon is valid, but its Swift form can't be written, so generation
/// stops before it writes any file. This is reported by throwing rather than
/// with `fatalError`, like `SchemaDecodeError.duplicateNSID`: it is a problem
/// in the input, so the command line reports it as an error and tests can
/// check it, and the generated file isn't left half written.
enum GeneratedNameCollisionError: Error, Equatable, CustomStringConvertible {
  /// `field` of the generated type `typeName`, from the schema `nsid`, has the
  /// name of the declaration `generatedName` that the generator adds to it.
  case field(nsid: String, typeName: String, field: String, generatedName: String)

  var description: String {
    switch self {
    case .field(let nsid, let typeName, let field, let generatedName):
      "field \(field) of \(typeName) (\(nsid)) collides with the generated \(generatedName); rename the field in the Lexicon"
    }
  }
}

/// Throws the first field, in a stable order, that would collide with a
/// declaration the generator adds to its type.
///
/// It walks the same types as code generation (`TypeSchema.allTypes(prefix:)`)
/// and asks the definitions the same questions the generator does, so that it
/// reports a collision exactly when the generated code would have one.
func checkGeneratedNameCollisions(schemasMap: [String: [Schema]], defMap: ExtDefMap) throws {
  let schemas = schemasMap.values.flatMap { $0 }.sorted { $0.id < $1.id }
  for schema in schemas {
    let types = schema.allTypes(prefix: schema.prefix).sorted { $0.key < $1.key }
    for (name, ts) in types {
      let namespace = Lex.structNameFor(prefix: ts.prefix)
      switch ts.type {
      case .object(let def):
        try checkObject(def, ts: ts, typeName: "\(namespace).\(name)", defMap: defMap)
      case .record(let def):
        try checkObject(def.record, ts: ts, typeName: "\(namespace).\(name)", defMap: defMap)
      case .query(let def) where def.paramsHaveConstraints:
        // `Input.Query` holds the parameters and their `Constraints`.
        let fields = (def.parameters?.properties.keys).map { Array($0) } ?? []
        try check(
          fields: fields, ts: ts, typeName: "\(namespace).\(ts.typeName).Input.Query",
          generatedName: ValidationDecl.constantsEnumName, display: "\(ValidationDecl.constantsEnumName) enum")
      default:
        break
      }
    }
  }
}

private func checkObject(_ def: ObjectTypeDefinition, ts: TypeSchema, typeName: String, defMap: ExtDefMap) throws {
  let fields = Array(def.properties.keys)
  if def.emitsConstraintConstants {
    try check(
      fields: fields, ts: ts, typeName: typeName,
      generatedName: ValidationDecl.constantsEnumName, display: "\(ValidationDecl.constantsEnumName) enum")
  }
  if def.emitsValidateConstraints(ts: ts, defMap: defMap) {
    try check(
      fields: fields, ts: ts, typeName: typeName,
      generatedName: ValidationDecl.methodName, display: "\(ValidationDecl.methodName)() method")
  }
}

private func check(fields: [String], ts: TypeSchema, typeName: String, generatedName: String, display: String) throws {
  if fields.contains(generatedName) {
    throw GeneratedNameCollisionError.field(nsid: ts.id, typeName: typeName, field: generatedName, generatedName: display)
  }
}
