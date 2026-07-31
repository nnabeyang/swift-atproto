import SwiftCbor

enum ATProtoCbor {
  static let decoderOptions: CborDecoder.Options = [
    .minimalArgumentEncoding,
    .definiteLengthItems,
    .lexicographicallySortedMapKeys,
    .stringMapKeysOnly,
    .basicSimpleValuesOnly,
    .validUTF8Only,
    .singleTopLevelItem,
    .floatingPointValuesDisallowed,
  ]

  static func decoder(limits: CborDecoder.Limits = .init()) -> CborDecoder {
    CborDecoder(options: decoderOptions, allowedTags: [42], limits: limits)
  }
}
