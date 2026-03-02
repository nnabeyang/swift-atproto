import Foundation
import SwiftSyntax

struct RecordDefinition: Encodable, DecodableWithConfiguration, SwiftCodeGeneratable {
  typealias DecodingConfiguration = TypeSchema.DecodingConfiguration

  var type: FieldType {
    .record
  }

  let key: String
  let record: ObjectTypeDefinition

  private enum CodingKeys: String, CodingKey {
    case type
    case key
    case record
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(String.self, forKey: .key)
    record = try container.decode(ObjectTypeDefinition.self, forKey: .record, configuration: configuration)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(key, forKey: .key)
    try container.encode(record, forKey: .record)
  }

  func generateDeclaration(leadingTrivia: Trivia? = nil, ts: TypeSchema, name: String, type typeName: String, defMap: ExtDefMap) -> any DeclSyntaxProtocol {
    record.generateDeclaration(leadingTrivia: leadingTrivia, ts: ts, name: name, type: typeName, defMap: defMap)
  }
}
