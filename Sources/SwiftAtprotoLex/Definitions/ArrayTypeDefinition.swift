import Foundation
import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

final class ArrayTypeDefinition: Encodable, DecodableWithConfiguration, Sendable, SwiftCodeGeneratable {
  var type: FieldType { .array }

  let items: FieldTypeDefinition
  let description: String?
  let minLength: Int?
  let maxLength: Int?

  private enum CodingKeys: String, CodingKey {
    case type
    case description
    case items
    case minLength
    case maxLength
  }

  init(from decoder: Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    items = try container.decode(FieldTypeDefinition.self, forKey: .items, configuration: configuration)
    minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
    maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(items, forKey: .items)
    try container.encodeIfPresent(maxLength, forKey: .maxLength)
    try container.encodeIfPresent(minLength, forKey: .minLength)
  }

  func generateDeclaration(
    leadingTrivia: Trivia?, ts: TypeSchema, name: String, type typeName: String,
    defMap: ExtDefMap, generate: GenerateOption
  ) -> any DeclSyntaxProtocol {
    let key = "elem"
    let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: key, type: items)
    let tname = TypeSchema.typeNameForField(name: name, k: key, v: ts, defMap: defMap)
    return VariableDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      bindingSpecifier: .keyword(.let)
    ) {
      PatternBindingSyntax(
        pattern: PatternSyntax("type"),
        initializer: InitializerClauseSyntax(
          value: StringLiteralExprSyntax(content: tname)
        )
      )
    }
  }
}
