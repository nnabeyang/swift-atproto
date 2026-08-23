import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `space-ref` string format.
struct SpaceRefInteropTests {
  static let did = "did:plc:ewvi7nxzyoun6zhxrhs64oiz"
  static let maxSkey = String(repeating: "a", count: 512)

  static let validSpaceRefs: [String] = [
    // Common forms.
    "at://\(did)/space/com.example.forum/self",
    "at://\(did)/space/com.example.forum/3jzfcijpj2z2a",
    // Allowed record-key punctuation in the space key.
    "at://\(did)/space/com.example.forum/abc-def",
    "at://\(did)/space/com.example.forum/abc_def",
    "at://\(did)/space/com.example.forum/abc.def",
    "at://\(did)/space/com.example.forum/abc:def",
    "at://\(did)/space/com.example.forum/abc~def",
    // Other DID methods.
    "at://did:web:example.com/space/com.example.forum/self",
    // Deeper NSID authority.
    "at://\(did)/space/com.example.sub.forum/self",
    // Space key at the 512-byte limit.
    "at://\(did)/space/com.example.forum/\(maxSkey)",
  ]

  static let invalidSpaceRefs: [String] = [
    // Missing or wrong scheme.
    "\(did)/space/com.example.forum/self",
    "https://\(did)/space/com.example.forum/self",
    // Missing `space` marker.
    "at://\(did)/com.example.forum/self",
    // Marker in the wrong position.
    "at://\(did)/com.example.forum/space/self",
    // Wrong marker.
    "at://\(did)/spaces/com.example.forum/self",
    // Too few segments.
    "at://\(did)/space/com.example.forum",
    "at://\(did)/space",
    "at://\(did)",
    // Too many segments: this is a record URI, not a space ref.
    "at://\(did)/space/com.example.forum/self/\(did)/com.example.post/3jzfcijpj2z2a",
    // Trailing slash.
    "at://\(did)/space/com.example.forum/self/",
    // Empty segments.
    "at:///space/com.example.forum/self",
    "at://\(did)/space//self",
    "at://\(did)/space/com.example.forum/",
    // Authority must be a DID, not a handle.
    "at://alice.example.com/space/com.example.forum/self",
    // Malformed DID.
    "at://did:plc:/space/com.example.forum/self",
    "at://did/space/com.example.forum/self",
    // Space type must be an NSID.
    "at://\(did)/space/forum/self",
    "at://\(did)/space/com.example/self",
    "at://\(did)/space/com.example.4forum/self",
    // Space key must be a record key.
    "at://\(did)/space/com.example.forum/.",
    "at://\(did)/space/com.example.forum/..",
    "at://\(did)/space/com.example.forum/\(maxSkey)a",
    "at://\(did)/space/com.example.forum/has space",
    // Query and fragment are not part of a space ref.
    "at://\(did)/space/com.example.forum/self?foo=bar",
    "at://\(did)/space/com.example.forum/self#/name",
  ]

  @Test func acceptsValidSpaceRefs() throws {
    for wire in Self.validSpaceRefs {
      let ref = try SpaceRef(string: wire)
      #expect(ref.rawValue == wire)
    }
  }

  @Test func rejectsInvalidSpaceRefs() {
    for wire in Self.invalidSpaceRefs {
      #expect(throws: LexiconStringFormatError.self) {
        try SpaceRef(string: wire)
      }
    }
  }

  @Test func exposesParsedComponents() throws {
    let ref = try SpaceRef(string: "at://\(Self.did)/space/com.example.forum/self")
    #expect(ref.spaceDid.rawValue == Self.did)
    #expect(ref.spaceType.rawValue == "com.example.forum")
    #expect(ref.skey.rawValue == "self")
  }

  @Test func lenientModeRelaxesOnlyTheSpaceKey() throws {
    let overlong = "at://\(Self.did)/space/com.example.forum/\(Self.maxSkey)a"
    #expect(throws: LexiconStringFormatError.self) { try SpaceRef(string: overlong) }
    let lenient = try SpaceRef(string: overlong, strict: false)
    #expect(lenient.rawValue == overlong)

    // The authority and the space type are validated in both modes.
    let handleAuthority = "at://alice.example.com/space/com.example.forum/self"
    #expect(throws: LexiconStringFormatError.self) {
      try SpaceRef(string: handleAuthority, strict: false)
    }
    let badType = "at://\(Self.did)/space/forum/self"
    #expect(throws: LexiconStringFormatError.self) {
      try SpaceRef(string: badType, strict: false)
    }

    // Lenient record-key handling does not relax the AT URI character set.
    for invalidKey in ["has space", "日本語", "double\"quote"] {
      let wire = "at://\(Self.did)/space/com.example.forum/\(invalidKey)"
      #expect(throws: LexiconStringFormatError.self) {
        try SpaceRef(string: wire, strict: false)
      }
    }
  }

  @Test func composesFromComponents() throws {
    let ref = try SpaceRef(
      spaceDid: try DID(string: Self.did),
      spaceType: try NSID(string: "com.example.forum"),
      skey: try RecordKey(string: "self")
    )
    #expect(ref.rawValue == "at://\(Self.did)/space/com.example.forum/self")
    #expect(ref.description == ref.rawValue)
    // The composed string round-trips through the parser.
    #expect(try SpaceRef(string: ref.rawValue).rawValue == ref.rawValue)
  }

  @Test func composingRejectsALenientRecordKey() throws {
    let lenientKey = try RecordKey(string: "\(Self.maxSkey)a", strict: false)
    #expect(throws: LexiconStringFormatError.self) {
      try SpaceRef(
        spaceDid: try DID(string: Self.did),
        spaceType: try NSID(string: "com.example.forum"),
        skey: lenientKey
      )
    }
  }
}
