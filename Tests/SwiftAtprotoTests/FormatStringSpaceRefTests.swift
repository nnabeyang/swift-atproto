import Foundation
import Testing

@testable import SwiftAtproto

struct FormatStringSpaceRefTests {
  static let wire = "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/self"

  @Test func decodePreservesWireStringAndTypedYieldsSpaceRef() throws {
    let data = Data("\"\(Self.wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<SpaceRef>.self, from: data)
    #expect(value.rawValue == Self.wire)
    #expect(value.typed?.rawValue == Self.wire)
    #expect(value.typed?.skey.rawValue == "self")
  }

  @Test func invalidSpaceRefDecodesLenientlyWithNilTyped() throws {
    let wire = "at://alice.example.com/space/com.example.forum/self"  // handle authority
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<SpaceRef>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
    #expect(value.typedLenient == nil)
  }

  @Test func overlongSpaceKeyIsTypedOnlyLeniently() throws {
    let wire =
      "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/"
      + String(repeating: "a", count: 513)
    let data = Data("\"\(wire)\"".utf8)
    let value = try JSONDecoder().decode(FormatString<SpaceRef>.self, from: data)
    #expect(value.rawValue == wire)
    #expect(value.typed == nil)
    #expect(value.typedLenient?.rawValue == wire)
  }

  @Test func encodeEmitsWireString() throws {
    let value = FormatString<SpaceRef>(rawValue: Self.wire)
    let encoder = JSONEncoder()
    // The wire string contains "/", which JSONEncoder escapes to "\/" by default.
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(value)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(Self.wire)\"")
  }
}
