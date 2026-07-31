import Foundation
import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct SubscriptionDefinition: Encodable, DecodableWithConfiguration, SwiftCodeGeneratable {
  var type: FieldType {
    .subscription
  }

  let parameters: Parameters?
  let message: MessageType?
  let description: String?
  let errors: [ErrorResponse]?

  private enum CodingKeys: String, CodingKey {
    case type
    case parameters
    case message
    case description
    case errors
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    parameters = try container.decodeIfPresent(Parameters.self, forKey: .parameters, configuration: configuration)
    message = try container.decodeIfPresent(MessageType.self, forKey: .message, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    errors = try container.decodeIfPresent([ErrorResponse].self, forKey: .errors)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(parameters, forKey: .parameters)
    try container.encodeIfPresent(message, forKey: .message)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(errors, forKey: .errors)
  }

  func rpcArguments(
    ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String,
    protocolRequirement: Bool
  ) -> [FunctionParameterSyntax] {
    guard let parameters else { return [] }
    let required = Set(parameters.required ?? [])
    return parameters.sortedProperties.map { name, field in
      let child = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: field)
      let typeName = TypeSchema.typeNameForField(
        name: fname, k: name, v: child, defMap: defMap, dropPrefix: false)
      let base = Lex.typeSyntax(typeName)
      return FunctionParameterSyntax(
        firstName: .lexIdentifier(name),
        type: required.contains(name) ? base : TypeSyntax(OptionalTypeSyntax(wrappedType: base)),
        defaultValue: required.contains(name) || protocolRequirement
          ? nil : InitializerClauseSyntax(value: NilLiteralExprSyntax()))
    }
  }

  private func rpcParameterExpression(
    id: String,
    prefix: String,
    name: String,
    field: FieldTypeDefinition,
    isRequired: Bool
  ) -> String {
    let child = TypeSchema(id: id, prefix: prefix, defName: name, type: field)
    let parameterCase = TypeSchema.paramNameForField(typeSchema: child)
    let reference = name.escapedSwiftKeyword
    if case .string(let definition) = field,
      definition.enum != nil
        || definition.knownValues != nil
        || definition.format?.swiftFormatTypeName != nil
    {
      return
        isRequired
        ? ".\(parameterCase)(\(reference).rawValue)"
        : ".\(parameterCase)(\(reference)?.rawValue)"
    }
    if case .array(let arrayDefinition) = field,
      case .string(let stringDefinition) = arrayDefinition.items,
      stringDefinition.format?.swiftFormatTypeName != nil
    {
      return
        isRequired
        ? ".\(parameterCase)(\(reference).map(\\.rawValue))"
        : ".\(parameterCase)(\(reference)?.map(\\.rawValue))"
    }
    return ".\(parameterCase)(\(reference))"
  }

  func generateDeclaration(
    leadingTrivia: Trivia?, ts: TypeSchema, name: String, type typeName: String,
    defMap: ExtDefMap, generate: GenerateOption
  ) -> any DeclSyntaxProtocol {
    let prefix = Lex.structNameFor(prefix: ts.prefix)
    let refs: [String]
    if let message, case .union(let union) = message.schema.type {
      refs = union.refs.map { $0.hasPrefix("#") ? ts.id + $0 : $0 }
    } else {
      refs = []
    }
    let messageTypes = refs.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
    let queryProperties = (parameters?.sortedProperties ?? []).map { parameter -> String in
      let child = TypeSchema(
        id: ts.id, prefix: ts.prefix, defName: parameter.0, type: parameter.1)
      let fieldType = TypeSchema.typeNameForField(
        name: name, k: parameter.0, v: child, defMap: defMap, dropPrefix: false)
      let required = Set(parameters?.required ?? []).contains(parameter.0)
      return "public var \(parameter.0.escapedSwiftKeyword): \(fieldType)\(required ? "" : "?")"
    }.joined(separator: "\n")
    let initArguments = rpcArguments(
      ts: ts, fname: name, defMap: defMap, prefix: prefix, protocolRequirement: false
    ).map(\.description).joined(separator: ", ")
    let assignments = (parameters?.sortedProperties ?? []).map {
      "self.\($0.0.escapedSwiftKeyword) = \($0.0.escapedSwiftKeyword)"
    }.joined(separator: "\n")
    let requiredParameters = Set(parameters?.required ?? [])
    let params = (parameters?.sortedProperties ?? []).map {
      "\"\($0.0)\": \(rpcParameterExpression(id: ts.id, prefix: ts.prefix, name: $0.0, field: $0.1, isRequired: requiredParameters.contains($0.0)))"
    }.joined(separator: ", ")
    let errorCases = (errors ?? []).sorted().map {
      "case \($0.name.camelCased())(Swift.String?)"
    }.joined(separator: "\n")
    let errorInitCases = (errors ?? []).sorted().map {
      "case \"\($0.name)\": self = .\($0.name.camelCased())(error.message)"
    }.joined(separator: "\n")
    let errorNameCases = (errors ?? []).sorted().map {
      "case .\($0.name.camelCased()): return \"\($0.name)\""
    }.joined(separator: "\n")
    let errorMessageCases = (errors ?? []).sorted().map {
      "case .\($0.name.camelCased())(let message): return message"
    }.joined(separator: "\n")
    let errorDeclaration = """
      public enum Error: XRPCError {
        \(errorCases)
        case unexpected(error: Swift.String?, message: Swift.String?)

        public init(error: UnExpectedError) {
          switch error.error {
          \(errorInitCases)
          default: self = .unexpected(error: error.error, message: error.message)
          }
        }

        public var error: Swift.String? {
          switch self {
          \(errorNameCases)
          case .unexpected(let error, _): return error
          }
        }

        public var message: Swift.String? {
          switch self {
          \(errorMessageCases)
          case .unexpected(_, let message): return message
          }
        }
      }
      """
    let source = """
      \(description.map { "/// \($0)\n" } ?? "")public enum \(ts.typeName): XRPCSubscription {
        public static let id = "\(typeName)"
        public static let messageTypes: Set<Swift.String> = [\(messageTypes)]
        public typealias Message = \(prefix).\(name)_Message
        public struct Input: XRPCQueryInput {
          public struct Query: XRPCInputQuery {
            \(queryProperties)
            public init(\(initArguments)) {
              \(assignments)
            }
            public var asParameters: Parameters? {
              Parameters(dictionary: [\(params)])
            }
          }
          public let query: Query
          public init(query: Query) { self.query = query }
        }
        \(errorDeclaration)
      }
      """
    let declaration = DeclSyntax(stringLiteral: source)
    return declaration
  }
}
