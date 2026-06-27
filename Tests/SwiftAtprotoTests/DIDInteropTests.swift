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
}
