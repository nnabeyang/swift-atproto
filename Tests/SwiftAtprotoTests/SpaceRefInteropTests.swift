import Foundation
import Testing

@testable import SwiftAtproto

// Wire-shape vectors for the lexicon `space-ref` string format.
struct SpaceRefInteropTests {
  static let did = "did:plc:ewvi7nxzyoun6zhxrhs64oiz"
  static let maxSkey = String(repeating: "a", count: 512)

  static let validSpaceRefs: [String] = [
    // Common forms.
    "at:space/\(did)/com.example.forum/self",
    "at:space/\(did)/com.example.forum/3jzfcijpj2z2a",
    // Allowed record-key punctuation in the space key.
    "at:space/\(did)/com.example.forum/abc-def",
    "at:space/\(did)/com.example.forum/abc_def",
    "at:space/\(did)/com.example.forum/abc.def",
    "at:space/\(did)/com.example.forum/abc:def",
    "at:space/\(did)/com.example.forum/abc~def",
    // Other DID methods, including did:web with an underscore or an encoded port.
    "at:space/did:web:example.com/com.example.forum/self",
    "at:space/did:web:foo_bar.example.com/com.example.forum/self",
    "at:space/did:web:localhost%3A1234/com.example.forum/self",
    // Deeper NSID authority.
    "at:space/\(did)/com.example.sub.forum/self",
    // Space key at the 512-byte limit.
    "at:space/\(did)/com.example.forum/\(maxSkey)",
  ]

  static let invalidSpaceRefs: [String] = [
    // Missing or wrong prefix.
    "\(did)/com.example.forum/self",
    "space/\(did)/com.example.forum/self",
    "https://\(did)/com.example.forum/self",
    "at:spaces/\(did)/com.example.forum/self",
    "at:Space/\(did)/com.example.forum/self",
    // A public AT URI is not a space ref.
    "at://\(did)/com.example.forum/self",
    // The legacy form is rejected in strict mode.
    "at://\(did)/space/com.example.forum/self",
    // Too few segments.
    "at:space/\(did)/com.example.forum",
    "at:space/\(did)",
    "at:space/",
    "at:space",
    // Too many segments: this is a record URI, not a space ref.
    "at:space/\(did)/com.example.forum/self/\(did)/com.example.post/3jzfcijpj2z2a",
    // Trailing slash.
    "at:space/\(did)/com.example.forum/self/",
    // Empty segments.
    "at:space//com.example.forum/self",
    "at:space/\(did)//self",
    "at:space/\(did)/com.example.forum/",
    // Authority must be a DID, not a handle.
    "at:space/alice.example.com/com.example.forum/self",
    // Malformed DID.
    "at:space/did:plc:/com.example.forum/self",
    "at:space/did/com.example.forum/self",
    // Space type must be an NSID.
    "at:space/\(did)/forum/self",
    "at:space/\(did)/com.example/self",
    "at:space/\(did)/com.example.4forum/self",
    // Space key must be a record key.
    "at:space/\(did)/com.example.forum/.",
    "at:space/\(did)/com.example.forum/..",
    "at:space/\(did)/com.example.forum/\(maxSkey)a",
    "at:space/\(did)/com.example.forum/has space",
    // Query and fragment are not part of a space ref.
    "at:space/\(did)/com.example.forum/self?foo=bar",
    "at:space/\(did)/com.example.forum/self#/name",
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
    let ref = try SpaceRef(string: "at:space/\(Self.did)/com.example.forum/self")
    #expect(ref.spaceDid.rawValue == Self.did)
    #expect(ref.spaceType.rawValue == "com.example.forum")
    #expect(ref.skey.rawValue == "self")
  }

  @Test func lenientModeReadsTheLegacyFormAsTheCurrentOne() throws {
    let legacy = "at://\(Self.did)/space/com.example.forum/self"
    let ref = try SpaceRef(string: legacy, strict: false)
    #expect(ref.rawValue == "at:space/\(Self.did)/com.example.forum/self")
    #expect(ref.spaceDid.rawValue == Self.did)
    #expect(ref.spaceType.rawValue == "com.example.forum")
    #expect(ref.skey.rawValue == "self")
    // The same space reads equal in either form.
    #expect(ref == (try SpaceRef(string: "at:space/\(Self.did)/com.example.forum/self")))
  }

  @Test(arguments: [
    // A legacy record URI is not a space ref.
    "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum/self/did:plc:ewvi7nxzyoun6zhxrhs64oiz/com.example.post/3jzfcijpj2z2a",
    // A handle authority stays invalid after the rewrite.
    "at://alice.example.com/space/com.example.forum/self",
    // Too few segments.
    "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/com.example.forum",
    "at://did:plc:ewvi7nxzyoun6zhxrhs64oiz/space/",
    "at:///space/com.example.forum/self",
  ])
  func lenientModeStillRejectsAMalformedLegacyRef(_ wire: String) {
    #expect(throws: LexiconStringFormatError.self) { try SpaceRef(string: wire, strict: false) }
  }

  @Test func lenientModeRelaxesOnlyTheSpaceKey() throws {
    let overlong = "at:space/\(Self.did)/com.example.forum/\(Self.maxSkey)a"
    #expect(throws: LexiconStringFormatError.self) { try SpaceRef(string: overlong) }
    let lenient = try SpaceRef(string: overlong, strict: false)
    #expect(lenient.rawValue == overlong)

    // The authority and the space type are validated in both modes.
    let handleAuthority = "at:space/alice.example.com/com.example.forum/self"
    #expect(throws: LexiconStringFormatError.self) {
      try SpaceRef(string: handleAuthority, strict: false)
    }
    let badType = "at:space/\(Self.did)/forum/self"
    #expect(throws: LexiconStringFormatError.self) {
      try SpaceRef(string: badType, strict: false)
    }

    // Lenient record-key handling does not relax the AT URI character set.
    for invalidKey in ["has space", "日本語", "double\"quote"] {
      let wire = "at:space/\(Self.did)/com.example.forum/\(invalidKey)"
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
    #expect(ref.rawValue == "at:space/\(Self.did)/com.example.forum/self")
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
