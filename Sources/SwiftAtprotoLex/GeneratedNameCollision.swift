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
  /// The schema `nsid` generates the type or namespace `typeName`, whose last
  /// component is the name of a module the generated code qualifies its
  /// references with (`Lex.qualifyingModules`), so it would hide that module.
  case moduleName(nsid: String, typeName: String)
  /// `fields` of the generated type `typeName` declare limits whose constants
  /// in its `Constraints` enum would all be named `name`, such as `tagsItem`'s
  /// `maxLength` and the `maxLength` of each element of `tags`.
  case constantName(nsid: String, typeName: String, name: String, fields: [String])

  var description: String {
    switch self {
    case .field(let nsid, let typeName, let field, let generatedName):
      "field \(field) of \(typeName) (\(nsid)) collides with the generated \(generatedName); rename the field in the Lexicon"
    case .moduleName(let nsid, let typeName):
      "\(nsid) generates \(typeName), which hides the \(typeName.split(separator: ".").last.map(String.init) ?? typeName) module that the generated code refers to; rename it in the Lexicon"
    case .constantName(let nsid, let typeName, let name, let fields):
      "fields \(fields.joined(separator: " and ")) of \(typeName) (\(nsid)) both generate the constant \(name) in its Constraints enum; rename one of them in the Lexicon"
    }
  }
}

/// Throws the first name, in a stable order, that the generated code can't
/// use: a field that would collide with a declaration the generator adds to
/// its type, two limits whose constants would have the same name, or a
/// generated type or namespace that would hide a module the generated code
/// refers to.
///
/// It walks the same types as code generation (`TypeSchema.allTypes(prefix:)`)
/// and asks the definitions the same questions the generator does, so that it
/// reports a collision exactly when the generated code would have one.
func checkGeneratedNameCollisions(schemasMap: [String: [Schema]], defMap: ExtDefMap) throws {
  let schemas = schemasMap.values.flatMap { $0 }.sorted { $0.id < $1.id }
  for schema in schemas {
    // The generated code is written inside extensions of these namespaces, so
    // each segment, like each generated type, is found before a module of the
    // same name when `Swift.String` or `SwiftAtproto.AnyCodable` is resolved.
    let namespaceSegments = Lex.structNameFor(prefix: schema.prefix).split(separator: ".").map(String.init)
    for (index, segment) in namespaceSegments.enumerated() where Lex.qualifyingModules.contains(segment) {
      throw GeneratedNameCollisionError.moduleName(
        nsid: schema.id, typeName: namespaceSegments[...index].joined(separator: "."))
    }
    let types = schema.allTypes(prefix: schema.prefix).sorted { $0.key < $1.key }
    for (name, ts) in types {
      let namespace = Lex.structNameFor(prefix: ts.prefix)
      if Lex.qualifyingModules.contains(name) {
        throw GeneratedNameCollisionError.moduleName(nsid: ts.id, typeName: "\(namespace).\(name)")
      }
      switch ts.type {
      case .object(let def):
        try checkObject(def, ts: ts, typeName: "\(namespace).\(name)", defMap: defMap)
      case .record(let def):
        try checkObject(def.record, ts: ts, typeName: "\(namespace).\(name)", defMap: defMap)
      case .query(let def) where def.paramsHaveConstraints:
        // `Input.Query` holds the parameters and their `Constraints`.
        let fields = (def.parameters?.properties.keys).map { Array($0) } ?? []
        let typeName = "\(namespace).\(ts.typeName).Input.Query"
        try check(
          fields: fields, ts: ts, typeName: typeName,
          generatedName: ValidationDecl.constantsEnumName, display: "\(ValidationDecl.constantsEnumName) enum")
        try checkConstantNames(of: def.parameters?.sortedProperties ?? [], ts: ts, typeName: typeName)
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
    try checkConstantNames(of: def.sortedProperties, ts: ts, typeName: typeName)
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

/// Throws when two fields of one type would declare a constant of the same
/// name in its `Constraints` enum. The names come from
/// `constraintConstantNames(for:)`, which the generator also declares them by.
private func checkConstantNames(of properties: [(String, FieldTypeDefinition)], ts: TypeSchema, typeName: String) throws {
  var owners: [String: String] = [:]
  for (key, property) in properties {
    for name in property.constraintConstantNames(for: key) {
      if let other = owners[name], other != key {
        throw GeneratedNameCollisionError.constantName(nsid: ts.id, typeName: typeName, name: name, fields: [other, key])
      }
      owners[name] = key
    }
  }
}
