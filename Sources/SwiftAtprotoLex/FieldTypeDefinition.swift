import Foundation
import SwiftSyntax

enum FieldTypeDefinition: Encodable, DecodableWithConfiguration, Sendable {
  typealias DecodingConfiguration = TypeSchema.DecodingConfiguration
  case token(TokenTypeDefinition)
  case null(NullTypeDefinition)
  case boolean(BooleanTypeDefinition)
  case integer(IntegerTypeDefinition)
  case blob(BlobTypeDefinition)
  case bytes(BytesTypeDefinition)
  case string(StringTypeDefinition)
  case union(UnionTypeDefinition)
  case array(ArrayTypeDefinition)
  case object(ObjectTypeDefinition)
  case ref(ReferenceTypeDefinition)
  case permission(PermissionTypeDefinition)
  case unknown(UnknownTypeDefinition)
  case cidLink(CidLinkTypeDefinition)
  case procedure(ProcedureTypeDefinition)
  case query(QueryTypeDefinition)
  case subscription(SubscriptionDefinition)
  case record(RecordDefinition)
  case permissionSet(PermissionSetTypeDefinition)
  private enum CodingKeys: String, CodingKey {
    case type
  }

  var isPrimitive: Bool {
    switch self {
    case .integer(let def):
      def.isPrimitive
    case .string(let def):
      def.isPrimitive
    case .union:
      false
    default:
      true
    }
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let type = try FieldType(rawValue: container.decode(String.self, forKey: .type)) else {
      throw DecodingError.typeMismatch(FieldTypeDefinition.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Invalid number of keys found, expected one.", underlyingError: nil))
    }
    switch type {
    case .token:
      self = try .token(TokenTypeDefinition(from: decoder))
    case .null:
      self = try .null(NullTypeDefinition(from: decoder))
    case .boolean:
      self = try .boolean(BooleanTypeDefinition(from: decoder))
    case .integer:
      self = try .integer(IntegerTypeDefinition(from: decoder))
    case .bytes:
      self = try .bytes(BytesTypeDefinition(from: decoder))
    case .blob:
      self = try .blob(BlobTypeDefinition(from: decoder))
    case .string:
      self = try .string(StringTypeDefinition(from: decoder))
    case .union:
      self = try .union(UnionTypeDefinition(from: decoder))
    case .array:
      self = try .array(ArrayTypeDefinition(from: decoder, configuration: configuration))
    case .object:
      self = try .object(ObjectTypeDefinition(from: decoder, configuration: configuration))
    case .ref:
      self = try .ref(ReferenceTypeDefinition(from: decoder))
    case .permission:
      self = try .permission(PermissionTypeDefinition(from: decoder))
    case .unknown:
      self = try .unknown(UnknownTypeDefinition(from: decoder))
    case .cidLink:
      self = try .cidLink(CidLinkTypeDefinition(from: decoder))
    case .procedure:
      self = try .procedure(ProcedureTypeDefinition(from: decoder, configuration: configuration))
    case .query:
      self = try .query(QueryTypeDefinition(from: decoder, configuration: configuration))
    case .subscription:
      self = try .subscription(SubscriptionDefinition(from: decoder, configuration: configuration))
    case .record:
      self = try .record(RecordDefinition(from: decoder, configuration: configuration))
    case .permissionSet:
      self = try .permissionSet(PermissionSetTypeDefinition(from: decoder))
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .token(let def):
      try def.encode(to: encoder)
    case .null(let def):
      try def.encode(to: encoder)
    case .boolean(let def):
      try def.encode(to: encoder)
    case .integer(let def):
      try def.encode(to: encoder)
    case .blob(let def):
      try def.encode(to: encoder)
    case .bytes(let def):
      try def.encode(to: encoder)
    case .string(let def):
      try def.encode(to: encoder)
    case .permission(let def):
      try def.encode(to: encoder)
    case .union(let def):
      try def.encode(to: encoder)
    case .array(let def):
      try def.encode(to: encoder)
    case .object(let def):
      try def.encode(to: encoder)
    case .ref(let def):
      try def.encode(to: encoder)
    case .unknown(let def):
      try def.encode(to: encoder)
    case .cidLink(let def):
      try def.encode(to: encoder)
    case .procedure(let def):
      try def.encode(to: encoder)
    case .query(let def):
      try def.encode(to: encoder)
    case .subscription(let def):
      try def.encode(to: encoder)
    case .record(let def):
      try def.encode(to: encoder)
    case .permissionSet(let def):
      try def.encode(to: encoder)
    }
  }

  func variable(name: String, type: TypeSyntax, isMutable: Bool = true) -> VariableDeclSyntax {
    VariableDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      bindingSpecifier: .keyword(isMutable ? .var : .let)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier(name.escapedSwiftKeyword)),
        typeAnnotation: TypeAnnotationSyntax(
          type: type
        )
      )
    }
  }

  var errors: [ErrorResponse]? {
    switch self {
    case .procedure(let t):
      t.errors
    case .query(let t):
      t.errors
    default:
      nil
    }
  }
}

extension FieldTypeDefinition: CustomStringConvertible {
  var description: String {
    switch self {
    case .token: "token"
    case .null: "null"
    case .boolean: "boolean"
    case .integer: "integer"
    case .blob: "blob"
    case .bytes: "bytes"
    case .string: "string"
    case .union: "union"
    case .array: "array"
    case .object: "object"
    case .ref: "ref"
    case .permission: "permission"
    case .unknown: "unknown"
    case .cidLink: "cidLink"
    case .procedure: "procedure"
    case .query: "query"
    case .subscription: "subscription"
    case .record: "record"
    case .permissionSet: "permissionSet"
    }
  }
}
