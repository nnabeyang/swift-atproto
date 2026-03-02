//
//  NullTypeDefinition.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2026/03/03.
//

struct NullTypeDefinition: Codable {
  var type: FieldType { .boolean }
  let description: String?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
  }
}
