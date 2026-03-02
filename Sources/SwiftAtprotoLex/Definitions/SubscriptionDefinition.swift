import Foundation

struct SubscriptionDefinition: Encodable, DecodableWithConfiguration {
  var type: FieldType {
    .subscription
  }

  let parameters: Parameters?
  let message: MessageType?

  private enum CodingKeys: String, CodingKey {
    case type
    case parameters
    case message
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    parameters = try container.decodeIfPresent(Parameters.self, forKey: .parameters, configuration: configuration)
    message = try container.decodeIfPresent(MessageType.self, forKey: .message, configuration: configuration)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(parameters, forKey: .parameters)
    try container.encodeIfPresent(message, forKey: .message)
  }
}
