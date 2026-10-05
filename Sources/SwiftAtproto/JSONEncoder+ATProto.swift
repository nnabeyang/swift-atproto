import Foundation

private enum ATProtoDataCodingKeys: String, CodingKey {
  case bytes = "$bytes"
}

extension JSONEncoder.DataEncodingStrategy {
  /// Encodes `Data` in the AT Protocol JSON representation.
  ///
  /// Lexicon `bytes` values are written as `{"$bytes": "<base64>"}`, using
  /// standard Base64 without padding. ``LexLink`` values are written as
  /// `{"$link": "<cid>"}`.
  ///
  /// Use this for any JSON that carries Lexicon data outside an XRPC call, such
  /// as a record you store or sign, or a response a server sends. XRPC calls
  /// made through the generated client already use it.
  ///
  /// A ``LexLink`` reaches this strategy as `Data`, its CID bytes prefixed with
  /// `0x00`, so the strategy cannot tell a link from a `bytes` value by type.
  /// `Data` whose first byte is `0x00` and whose remaining bytes parse as a CID
  /// is therefore written as `$link`. A `bytes` value that happens to have that
  /// shape is written as `$link` as well.
  ///
  /// See [Data Model](https://atproto.com/specs/data-model).
  public static var atproto: Self {
    .custom { data, encoder in
      // A failed CID parse means the value was never a `LexLink`.
      if data.first == 0, (try? LexLink.dataEncodingStrategy(data: data, encoder: encoder)) != nil {
        return
      }
      var container = encoder.container(keyedBy: ATProtoDataCodingKeys.self)
      try container.encode(
        data.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "=")),
        forKey: .bytes
      )
    }
  }
}

extension JSONDecoder.DataDecodingStrategy {
  /// Decodes `Data` from the AT Protocol JSON representation.
  ///
  /// Accepts a `{"$bytes": "<base64>"}` object with or without Base64 padding,
  /// and also a bare Base64 string, which older services emit. Throws a
  /// `DecodingError` when an object has no string `$bytes` member or the value
  /// is not valid Base64.
  ///
  /// ``LexLink`` decodes `{"$link": "<cid>"}` itself, so this strategy needs no
  /// counterpart to the inference that
  /// `JSONEncoder.DataEncodingStrategy.atproto` performs.
  ///
  /// See [Data Model](https://atproto.com/specs/data-model).
  public static var atproto: Self {
    .custom { decoder in
      let encoded: String
      if let container = try? decoder.container(keyedBy: ATProtoDataCodingKeys.self) {
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
