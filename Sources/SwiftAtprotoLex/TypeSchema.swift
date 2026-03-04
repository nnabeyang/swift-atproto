import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct TypeInfo {
  let name: String
  let type: TypeSchema
}

final class Schema: Encodable, DecodableWithConfiguration, Sendable {
  let prefix: String
  let lexicon: Int
  let id: String
  let revision: Int?
  let description: String?
  let defs: [String: TypeSchema]

  private enum CodingKeys: String, CodingKey {
    case lexicon
    case id
    case revision
    case description
    case defs
  }

  init(from decoder: any Decoder, configuration prefix: String) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.lexicon = try container.decode(Int.self, forKey: .lexicon)
    self.id = try container.decode(String.self, forKey: .id)
    self.revision = try container.decodeIfPresent(Int.self, forKey: .revision)
    self.description = try container.decodeIfPresent(String.self, forKey: .description)
    let nestedContainer = try container.nestedContainer(keyedBy: AnyCodingKeys.self, forKey: .defs)
    var defs = [String: TypeSchema]()
    for key in nestedContainer.allKeys {
      defs[key.stringValue] = try nestedContainer.decode(TypeSchema.self, forKey: key, configuration: .init(prefix: prefix, id: id, defName: key.stringValue))
    }
    self.defs = defs
    self.prefix = prefix
  }

  func allTypes(prefix: String) -> [String: TypeSchema] {
    var out = [String: TypeSchema]()
    let id = id
    var walk: ((String, TypeSchema?) -> Void)? = nil
    walk = { (name: String, ts: TypeSchema?) in
      guard let ts else {
        fatalError(#"nil type schema in "\#(name)"(\#(self.id)) "#)
      }
      switch ts.type {
      case .object(let def):
        out[name] = ts
        for (key, val) in def.properties {
          let childname = "\(name)_\(key.titleCased())"
          let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
          walk?(childname, ts)
        }
      case .union:
        out[name] = ts
      case .array(let def):
        let key = "\(name)_Elem"
        let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: def.items)
        walk?(key, ts)
      case .ref:
        break
      case .procedure(let def):
        out[name] = ts
        if let input = def.input, let schema = input.schema {
          walk?("\(name)_Input", schema)
        }
        if let output = def.output, let schema = output.schema {
          walk?("\(name)_Output", schema)
        }
      case .query(let def):
        out[name] = ts
        if let output = def.output, let schema = output.schema {
          walk?("\(name)_Output", schema)
        }
        if let parameters = def.parameters {
          for (key, val) in parameters.properties {
            let childname = "\(name)_\(key.titleCased())"
            let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
            walk?(childname, ts)
          }
        }
      case .record(let def):
        let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: "", type: .record(def))
        out[name] = ts
        for (key, val) in def.record.properties {
          let childname = "\(name)_\(key.titleCased())"
          let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
          walk?(childname, ts)
        }
      case .string(let def):
        guard def.knownValues != nil || def.enum != nil else { break }
        out[name] = ts
      default:
        break
      }
    }
    let tname = Lex.nameFromId(id: id, prefix: prefix)
    for elem in defs {
      let name = elem.key
      let n: String =
        if name == "main" {
          tname
        } else {
          "\(tname)_\(name.titleCased())"
        }
      walk?(n, elem.value)
    }
    return out
  }

  var name: String {
    let p = id.split(separator: ".")
    let count = p.count
    guard count >= 2 else { return p.first.map { String($0) } ?? "" }
    return "\(p[count - 2])\(p[count - 1])"
  }
}

typealias ExtDefMap = [String: ExtDef]

final class TypeSchema: Encodable, DecodableWithConfiguration, Sendable {
  struct DecodingConfiguration {
    let prefix: String
    let id: String
    let defName: String
  }

  enum CodingKeys: String, CodingKey {
    case type
  }

  let prefix: String
  let id: String
  let defName: String

  let type: FieldTypeDefinition

  var isRecord: Bool {
    switch type {
    case .record: true
    default: false
    }
  }

  init(id: String, prefix: String, defName: String, type: FieldTypeDefinition) {
    self.id = id
    self.prefix = prefix
    self.defName = defName
    self.type = type
  }

  required init(from decoder: Decoder, configuration: DecodingConfiguration) throws {
    type = try FieldTypeDefinition(from: decoder, configuration: configuration)

    id = configuration.id
    prefix = configuration.prefix
    defName = configuration.defName
  }

  func encode(to encoder: Encoder) throws {
    try type.encode(to: encoder)
  }

  func lookupRef(ref: String, defMap: ExtDefMap) -> TypeSchema {
    let fqref: String =
      if ref.hasPrefix("#") {
        "\(id)\(ref)"
      } else if ref.hasSuffix("#main") {
        String(ref.dropLast(5))
      } else {
        ref
      }
    guard let rr = defMap[fqref] else {
      fatalError("no such ref: \(fqref)")
    }
    let t = rr.type
    return t
  }

  func namesFromRef(ref: String, defMap: ExtDefMap, dropPrefix: Bool = true) -> (String, String) {
    let ts = lookupRef(ref: ref, defMap: defMap)
    if ts.prefix == "" {
      fatalError("no prefix for referenced type: \(ts.id)")
    }
    if prefix == "" {
      fatalError(#"no prefix for referencing type: \#(id) \#(defName)"#)
    }
    if case .string(let def) = ts.type, def.knownValues == nil, def.enum == nil {
      return ("INVALID", "String")
    }
    let tname: String =
      if ts.isRecord {
        "\(Lex.structNameFor(prefix: ts.prefix))_\(ts.typeName)"
      } else if dropPrefix, ts.prefix == prefix {
        ts.typeName
      } else {
        "\(Lex.structNameFor(prefix: ts.prefix)).\(ts.typeName)"
      }
    let vname: String =
      if tname.contains(where: { $0 == "." }) {
        String(tname.split(separator: ".")[1])
      } else {
        tname
      }
    return (vname, tname)
  }

  var typeName: String {
    guard !id.isEmpty else {
      fatalError("type schema hint fields not set")
    }
    guard !prefix.isEmpty else {
      fatalError("why no prefix?")
    }
    let baseType: String =
      if defName != "main" {
        "\(Lex.nameFromId(id: id, prefix: prefix))_\(defName.titleCased())"
      } else {
        Lex.nameFromId(id: id, prefix: prefix)
      }
    if case .array(let def) = type {
      if def.items.isPrimitive {
        return "[\(baseType)]"
      } else {
        return "[\(baseType)_Elem]"
      }
    } else {
      return baseType
    }
  }

  var isMethod: Bool {
    switch type {
    case .procedure, .query: true
    default: false
    }
  }

  static func typeNameForField(name: String, k: String, v: TypeSchema, defMap: ExtDefMap, dropPrefix: Bool = true) -> String {
    switch v.type {
    case .boolean:
      return "Bool"
    case .blob:
      return "LexBlob"
    case .bytes:
      return "Data"
    case .string(let def):
      if def.isPrimitive {
        return "String"
      }
      if !dropPrefix {
        return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
      } else {
        return "\(name)_\(k.titleCased())"
      }
    case .integer(let def):
      if def.isPrimitive {
        return "Int"
      }
      if !dropPrefix {
        return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
      } else {
        return "\(name)_\(k.titleCased())"
      }
    case .unknown:
      return "UnknownATPValue"
    case .cidLink:
      return "LexLink"
    case .ref(let def):
      let (_, tn) = v.namesFromRef(ref: def.ref, defMap: defMap, dropPrefix: dropPrefix)
      return tn
    case .array(let def):
      let ts = TypeSchema(id: v.id, prefix: v.prefix, defName: "Elem", type: def.items)
      let subt = Self.typeNameForField(name: "\(name)_\(k.titleCased())", k: "Elem", v: ts, defMap: defMap, dropPrefix: dropPrefix)
      return "[\(subt)]"
    case .union, .object:
      if !dropPrefix {
        return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
      } else {
        return "\(name)_\(k.titleCased())"
      }
    default:
      fatalError("field \(k) in \(name) has unsupported type name (\(v.type))")
    }
  }

  static func paramNameForField(typeSchema: TypeSchema) -> String {
    switch typeSchema.type {
    case .boolean:
      "bool"
    case .string:
      "string"
    case .integer:
      "integer"
    case .array:
      "array"
    default:
      fatalError("unexpected type for parameter name: \(typeSchema.type)")
    }
  }

  var httpMethod: String {
    switch type {
    case .procedure:
      ".post"
    case .query:
      ".get"
    default:
      fatalError()
    }
  }

  func writeRPC(leadingTrivia: Trivia? = nil, def: any HTTPAPITypeDefinition, typeName: String, defMap: ExtDefMap, prefix: String) -> DeclSyntaxProtocol {
    let fname = typeName
    let arguments = def.rpcArguments(ts: self, fname: fname, defMap: defMap, prefix: prefix)
    let output = def.rpcOutput(ts: self, fname: fname, defMap: defMap, prefix: prefix)
    return FunctionDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.mutating)),
      ],
      name: .identifier(typeName),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          arguments
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: .keyword(.async),
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: output
      )
    ) {
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let)
      ) {
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .identifier("params")),
          typeAnnotation: TypeAnnotationSyntax(
            type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("Parameters")))
          ),
          initializer: InitializerClauseSyntax(
            value: def.rpcParams(id: id, prefix: prefix)
          )
        )
      }
      DoStmtSyntax(
        catchClauses: [
          CatchClauseSyntax(
            CatchItemListSyntax {
              CatchItemSyntax(
                pattern: ValueBindingPatternSyntax(
                  bindingSpecifier: .keyword(.let),
                  pattern: ExpressionPatternSyntax(
                    expression: SequenceExprSyntax {
                      PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("error")))
                      UnresolvedAsExprSyntax()
                      TypeExprSyntax(type: IdentifierTypeSyntax(name: "UnExpectedError"))
                    }
                  )
                )
              )
            }
          ) {
            ThrowStmtSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(typeName), .identifier("Error")])
              ) {
                LabeledExprSyntax(label: .identifier("error"), colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("error")))
              }
            )
          }
        ]
      ) {
        ReturnStmtSyntax(
          expression: TryExprSyntax(
            expression:
              AwaitExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: DeclReferenceExprSyntax(baseName: .identifier("fetch"))
                ) {
                  LabeledExprSyntax(label: "endpoint", colon: .colonToken(), expression: StringLiteralExprSyntax(content: self.id))
                  LabeledExprSyntax(label: "contentType", colon: .colonToken(), expression: StringLiteralExprSyntax(content: def.contentType))
                  LabeledExprSyntax(label: "httpMethod", colon: .colonToken(), expression: ExprSyntax(stringLiteral: httpMethod))
                  LabeledExprSyntax(label: "params", colon: .colonToken(), expression: ExprSyntax("params"))
                  LabeledExprSyntax(label: "input", colon: .colonToken(), expression: def.inputRPCValue)
                  LabeledExprSyntax(label: "retry", colon: .colonToken(), expression: ExprSyntax("true"))
                }
              )
          )
        )
      }
    }
  }

  func typeIdentifier(name: String, property: FieldTypeDefinition, defMap: ExtDefMap, key: String, isRequired: Bool, dropPrefix: Bool = true) -> TypeSyntax {
    let type: TypeSyntax
    if case .string(let def) = property, def.enum != nil || def.knownValues != nil {
      let tn = "\(name)_\(key.titleCased())"
      type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(!dropPrefix ? "\(Lex.structNameFor(prefix: prefix)).\(tn)" : tn)))
    } else {
      let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: property)
      let tn = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, dropPrefix: dropPrefix)
      type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(tn)))
    }
    if isRequired {
      return type
    } else {
      return TypeSyntax(OptionalTypeSyntax(wrappedType: type))
    }
  }

  func lex(leadingTrivia: Trivia? = nil, name: String, type typeName: String, defMap: ExtDefMap, generate: GenerateOption) -> DeclSyntaxProtocol {
    switch type {
    case .string(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    case .object(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    case .record(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    case .union(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    case .array(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    case .procedure(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    case .query(let def):
      def.generateDeclaration(leadingTrivia: leadingTrivia, ts: self, name: name, type: typeName, defMap: defMap, generate: generate)
    default:
      fatalError()
    }
  }
}

struct ExtDef {
  let type: TypeSchema
}

struct Param: Codable {
  let type: String
  let maximum: Int
  let required: Bool
}

enum PrimaryType {
  case query
  case procedure
  case subscription
  case record
}

enum FieldType: String, Codable {
  case null
  case boolean
  case integer
  case string
  case bytes
  case cidLink = "cid-link"
  case blob
  case union
  case array
  case object
  case ref
  case permission
  case token
  case unknown
  case procedure
  case query
  case subscription
  case record
  case permissionSet = "permission-set"
}

enum AtpType {
  case concrete
  case container
  case meta
  case primary
}

struct StringFormat: Codable, RawRepresentable {
  typealias RawValue = String
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self.rawValue = rawValue
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let atIdentifier: Self = .init("at-identifier")
  static let atUri: Self = .init("at-uri")
  static let cid: Self = .init("cid")
  static let datetime: Self = .init("datetime")
  static let did: Self = .init("did")
  static let handle: Self = .init("handle")
  static let nsid: Self = .init("nsid")
  static let uri: Self = .init("uri")
  static let language: Self = .init("language")
  static let tid: Self = .init("tid")
  static let recordKey: Self = .init("record-key")
}

struct RecordSchema {
  let type: PrimaryType = .record
  let key: String
  let properties: [String: TypeSchema]
  let required: [String]?
  let nullable: [String]?
}

enum EncodingType: String, Codable {
  case cbor = "application/cbor"
  case json = "application/json"
  case jsonl = "application/jsonl"
  case car = "application/vnd.ipld.car"
  case text = "text/plain"
  case mp4 = "video/mp4"
  case any = "*/*"

  init(from decoder: Decoder) throws {
    let rawValue = try String(from: decoder)

    guard let value = EncodingType(rawValue: rawValue) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unexpected mimetype: \(rawValue.debugDescription)"))
    }
    self = value
  }

  func encode(to encoder: Encoder) throws {
    try rawValue.encode(to: encoder)
  }
}

struct OutputType: Encodable, DecodableWithConfiguration {
  let encoding: EncodingType
  let schema: TypeSchema?
  let description: String?

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    encoding = try container.decode(EncodingType.self, forKey: .encoding)
    schema = try container.decodeIfPresent(TypeSchema.self, forKey: .schema, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
  }
}

struct MessageType: Encodable, DecodableWithConfiguration {
  let description: String?
  let schema: TypeSchema

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    schema = try container.decode(TypeSchema.self, forKey: .schema, configuration: configuration)
  }
}

typealias InputType = OutputType

struct Parameters: Encodable, DecodableWithConfiguration {
  var type: String {
    "params"
  }

  let required: [String]?
  let properties: [String: FieldTypeDefinition]
  var sortedProperties: [(String, FieldTypeDefinition)] {
    properties.keys.sorted().compactMap {
      guard let property = properties[$0] else { return nil }
      return ($0, property)
    }
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    required = try container.decodeIfPresent([String].self, forKey: .required)
    var properties = [String: FieldTypeDefinition]()
    let nestedContainer = try container.nestedContainer(keyedBy: AnyCodingKeys.self, forKey: .properties)
    for key in nestedContainer.allKeys {
      properties[key.stringValue] = try nestedContainer.decode(FieldTypeDefinition.self, forKey: key, configuration: configuration)
    }
    self.properties = properties
  }
}

struct ErrorResponse: Codable, Equatable, Hashable {
  let name: String
  let description: String?

  func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }

  static func == (lhs: ErrorResponse, rhs: ErrorResponse) -> Bool {
    lhs.name == rhs.name
  }
}

extension ErrorResponse: Comparable {
  static func < (lhs: ErrorResponse, rhs: ErrorResponse) -> Bool {
    lhs.name < rhs.name
  }
}

func decodableInitializerDeclSyntax(
  leadingTrivia: Trivia? = nil,
  @CodeBlockItemListBuilder bodyBuilder: () throws -> CodeBlockItemListSyntax?
) rethrows -> InitializerDeclSyntax {
  try InitializerDeclSyntax(
    leadingTrivia: leadingTrivia,
    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
    signature: FunctionSignatureSyntax(
      parameterClause: FunctionParameterClauseSyntax {
        FunctionParameterSyntax(
          firstName: .identifier("from"),
          secondName: .identifier("decoder"),
          type: SomeOrAnyTypeSyntax(
            someOrAnySpecifier: .keyword(.any),
            constraint: IdentifierTypeSyntax(name: .identifier("Decoder"))
          )
        )

      },
      effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
    ),
    bodyBuilder: bodyBuilder
  )
}

func encodableFunctionDeclSyntax(leadingTrivia: Trivia? = nil, @CodeBlockItemListBuilder bodyBuilder: () throws -> CodeBlockItemListSyntax?) rethrows -> FunctionDeclSyntax {
  try FunctionDeclSyntax(
    leadingTrivia: leadingTrivia,
    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
    name: .identifier("encode"),
    signature: FunctionSignatureSyntax(
      parameterClause: FunctionParameterClauseSyntax {
        FunctionParameterSyntax(
          firstName: .identifier("to"),
          secondName: .identifier("encoder"),
          type: SomeOrAnyTypeSyntax(
            someOrAnySpecifier: .keyword(.any),
            constraint: IdentifierTypeSyntax(name: .identifier("Encoder"))
          )
        )
      },
      effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
    ), bodyBuilder: bodyBuilder)
}
