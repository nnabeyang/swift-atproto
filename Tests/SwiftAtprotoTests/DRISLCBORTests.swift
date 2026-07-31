import Foundation
import SwiftCbor
import Testing

@testable import SwiftAtproto

@Suite("DRISL-CBOR profile")
struct DRISLCBORTests {
  @Test("prefix decoding reports consumed bytes")
  func prefixDecode() throws {
    let decoder = ATProtoCbor.decoder()
    let result = try decoder.decodePrefix(Int.self, from: Data([0x01, 0x02]))
    #expect(result.value == 1)
    #expect(result.bytesConsumed == 1)
  }

  @Test("full decoding rejects trailing bytes")
  func rejectsTrailingBytes() {
    let decoder = ATProtoCbor.decoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(Int.self, from: Data([0x01, 0x02]))
    }
  }

  @Test("AT Protocol profile rejects floats")
  func rejectsFloats() {
    let decoder = ATProtoCbor.decoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(Double.self, from: Data([0xfb, 0, 0, 0, 0, 0, 0, 0, 0]))
    }
  }

  @Test("canonical maps reject duplicate keys")
  func rejectsDuplicateMapKeys() {
    let decoder = ATProtoCbor.decoder()
    let duplicate = Data([0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02])
    #expect(throws: DecodingError.self) {
      try decoder.decode([String: Int].self, from: duplicate)
    }
  }

  @Test("truncated input throws instead of trapping")
  func rejectsTruncatedInput() {
    let decoder = ATProtoCbor.decoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(Data.self, from: Data([0x5a, 0, 0, 0, 4, 1]))
    }
  }

  @Test("configured string and container limits are enforced")
  func enforcesLimits() {
    let decoder = ATProtoCbor.decoder(
      limits: .init(
        maximumNestingDepth: 2, maximumContainerElements: 1,
        maximumStringBytes: 2))
    #expect(throws: DecodingError.self) {
      try decoder.decode([Int].self, from: Data([0x82, 0x01, 0x02]))
    }
    #expect(throws: DecodingError.self) {
      try decoder.decode(String.self, from: Data([0x63, 0x61, 0x62, 0x63]))
    }
  }
}
