import Foundation
import SwiftSyntax

protocol HTTPAPITypeDefinition: Encodable, DecodableWithConfiguration {
  associatedtype DecodingConfiguration = TypeSchema.DecodingConfiguration
  var type: FieldType { get }
  var parameters: Parameters? { get }
  var output: OutputType? { get }
  var input: InputType? { get }
  var description: String? { get }
  var errors: [ErrorResponse]? { get }

  var contentType: String { get }
  var inputRPCValue: ExprSyntax { get }
  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [FunctionParameterSyntax]
  func rpcOutput(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> ReturnClauseSyntax
  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol
}

private enum HTTPAPITypedCodingKeys: String, CodingKey {
  case type
  case parameters
  case output
  case input
  case description
}

extension HTTPAPITypeDefinition {
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: HTTPAPITypedCodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(parameters, forKey: .parameters)
    try container.encodeIfPresent(output, forKey: .output)
    try container.encodeIfPresent(input, forKey: .input)
    try container.encodeIfPresent(description, forKey: .description)
  }

  var contentType: String {
    if let input {
      switch input.encoding {
      case .json, .jsonl, .text, .mp4:
        return input.encoding.rawValue
      case .cbor, .any, .car:
        return "*/*"
      }
    }
    return "*/*"
  }

  var inputRPCValue: ExprSyntax {
    ExprSyntax(stringLiteral: input != nil ? "input" : "Bool?.none")
  }

  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [FunctionParameterSyntax] {
    var arguments = [FunctionParameterSyntax]()
    if let input {
      switch input.encoding {
      case .cbor, .any, .car, .mp4:
        let tname = "Data"
        let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
      case .text:
        let tname = "String"
        let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
      case .json, .jsonl:
        let tname: String
        if case .ref(let ref) = input.schema?.type {
          (_, tname) = ts.namesFromRef(ref: ref.ref, defMap: defMap)
        } else {
          tname = "\(fname)_Input"
        }
        let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: "\(prefix).\(tname)"), trailingComma: comma))
      }
    }

    if let parameters {
      var required = [String: Bool]()
      for req in parameters.required ?? [] {
        required[req] = true
      }
      let count = parameters.properties.count
      var i = 0
      for (name, t) in parameters.sortedProperties {
        i += 1
        let isRequired = required[name] ?? false
        let tn: String
        if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
          tn = "\(prefix).\(fname)_\(name.titleCased())"
        } else {
          let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
          tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, dropPrefix: false)
        }
        let type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(tn)))
        let comma: TokenSyntax? = i == count ? nil : .commaToken()
        let defaultValue: InitializerClauseSyntax? =
          isRequired
          ? nil
          : InitializerClauseSyntax(
            equal: .equalToken(),
            value: NilLiteralExprSyntax()
          )
        arguments.append(
          .init(
            firstName: .identifier(name),
            type: isRequired
              ? type
              : TypeSyntax(OptionalTypeSyntax(wrappedType: type)), defaultValue: defaultValue, trailingComma: comma))
      }
    }
    return arguments
  }

  func rpcOutput(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> ReturnClauseSyntax {
    if let output {
      switch output.encoding {
      case .json, .jsonl:
        guard let schema = output.schema else {
          return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "EmptyResponse"))
        }
        let outname: String
        if case .ref(let def) = schema.type {
          (_, outname) = ts.namesFromRef(ref: def.ref, defMap: defMap)
        } else {
          outname = "\(fname)_Output"
        }
        return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "\(prefix).\(outname)"))
      case .text:
        return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "String"))
      case .cbor, .car, .any, .mp4:
        return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "Data"))
      }
    }
    return ReturnClauseSyntax(type: TypeSyntax("Bool"))
  }

  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol {
    if let parameters, !parameters.properties.isEmpty {
      var required = [String: Bool]()
      for req in parameters.required ?? [] {
        required[req] = true
      }
      return DictionaryExprSyntax {
        for (name, t) in parameters.sortedProperties {
          let ts = TypeSchema(id: id, prefix: prefix, defName: name, type: t)
          let tn = TypeSchema.paramNameForField(typeSchema: ts)
          let isRequired = required[name] ?? false
          let stringLiteral =
            if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
              isRequired ? ".\(tn)(\(name).rawValue)" : ".\(tn)(\(name)?.rawValue)"
            } else {
              ".\(tn)(\(name))"
            }
          DictionaryElementSyntax(
            key: StringLiteralExprSyntax(content: name),
            value: ExprSyntax(stringLiteral: stringLiteral)
          )
        }
      }
    } else {
      return NilLiteralExprSyntax()
    }
  }
}
