import SwiftSyntax

struct ProcedureTypeDefinition: HTTPAPITypeDefinition {
  var type: FieldType { .procedure }
  let parameters: Parameters?
  let output: OutputType?
  let input: InputType?
  let description: String?
  let errors: [ErrorResponse]?

  private enum CodingKeys: String, CodingKey {
    case type
    case parameters
    case output
    case input
    case description
    case errors
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    parameters = try container.decodeIfPresent(Parameters.self, forKey: .parameters, configuration: configuration)
    output = try container.decodeIfPresent(OutputType.self, forKey: .output, configuration: configuration)
    input = try container.decodeIfPresent(InputType.self, forKey: .input, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    errors = try container.decodeIfPresent([ErrorResponse].self, forKey: .errors)
  }
}
