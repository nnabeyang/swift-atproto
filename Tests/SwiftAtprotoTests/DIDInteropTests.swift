import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `did` string format. The `rawValue` is preserved verbatim.
struct DIDInteropTests {
  static let validDIDs: [String] = [
    // PLC method (typical atproto identity).
    "did:plc:7iza6de2dwap2sbkpav7c6c6",
    "did:plc:abc",
    // Web method (server-anchored identity).
    "did:web:example.com",
    "did:web:example.com:path",
    "did:web:example.com:user:alice",
    // Minimal form: single-character method, single-character identifier.
    "did:m:v",
    // Identifier may contain ALPHA / DIGIT / "." / "_" / ":" / "%" / "-".
    "did:method:abc.def",
    "did:method:abc-def",
    "did:method:abc_def",
    "did:method:abc:def:ghi",
    "did:method:abc123",
    "did:method:%41%42",
    // Long method name (lowercase ASCII only).
    "did:longmethodname:identifier",
  ]

  @Test(arguments: validDIDs)
  func validParses(_ input: String) throws {
    let did = try DID(string: input)
    #expect(did.rawValue == input)
  }

  static let invalidDIDs: [String] = [
    // Empty / scheme-only / method-only.
    "", "did:", "did::", "did:method", "did:method:",
    // Wrong-case scheme or method (grammar is lowercase-only).
    "DID:method:val", "did:METHOD:val", "did:Method:val",
    // Method must be `[a-z]+` — no digits, hyphens, dots, or underscores.
    "did:m3thod:val", "did:1method:val", "did:method-x:val", "did:method.x:val",
    "did:method_x:val",
    // Identifier must not end with `:` or `%`.
    "did:method:val:", "did:method:val%",
    // Whitespace and control characters anywhere break wire-shape.
    "did:method:val ", "did:method:val\t", "did:method:val\n", "did:method:val\u{0001}",
    "did:method:val\u{007F}", " did:method:val",
    // Disallowed identifier bytes.
    "did:method:val/path", "did:method:val[x]", "did:method:val#frag", "did:method:val?q",
    // Missing prefix or out-of-order.
    "didmethod:val", "1did:method:val", ":did:method:val",
  ]

  @Test(arguments: invalidDIDs)
  func invalidThrows(_ input: String) {
    #expect(throws: (any Error).self) { try DID(string: input) }
  }

  @Test func acceptsExactly2048ByteInput() throws {
    // "did:m:" (6 byte) + 2042-byte identifier = 2048 byte total (cap).
    let identifier = String(repeating: "a", count: 2048 - 6)
    let input = "did:m:" + identifier
    let did = try DID(string: input)
    #expect(did.rawValue.utf8.count == 2048)
  }

  @Test func rejectsOver2048ByteInput() {
    let identifier = String(repeating: "a", count: 2048 - 5)
    let input = "did:m:" + identifier
    #expect(input.utf8.count == 2049)
    #expect(throws: (any Error).self) { try DID(string: input) }
  }
}
