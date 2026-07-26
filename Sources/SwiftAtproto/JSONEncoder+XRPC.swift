import Foundation

private enum XRPCDataCodingKeys: String, CodingKey {
  case bytes = "$bytes"
}

extension JSONEncoder.DataEncodingStrategy {
  internal static var xrpc: Self {
    .custom { data, encoder in
      do {
        if !data.isEmpty, data[0] == 0 {
          try LexLink.dataEncodingStrategy(data: data, encoder: encoder)
          return
        }
      } catch {}
      var container = encoder.container(keyedBy: XRPCDataCodingKeys.self)
      try container.encode(
        data.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "=")),
        forKey: .bytes
      )
    }
  }
}

extension JSONDecoder.DataDecodingStrategy {
  internal static var xrpc: Self {
    .custom { decoder in
      let encoded: String
      if let container = try? decoder.container(keyedBy: XRPCDataCodingKeys.self) {
        encoded = try container.decode(String.self, forKey: .bytes)
      } else {
        let container = try decoder.singleValueContainer()
        encoded = try container.decode(String.self)
      }
      let padding = String(repeating: "=", count: (4 - encoded.count % 4) % 4)
      guard let data = Data(base64Encoded: encoded + padding) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "Invalid Base64 value for AT Protocol bytes"
          )
        )
      }
      return data
    }
  }
}
