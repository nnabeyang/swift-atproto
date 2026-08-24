import Foundation
import Testing

@testable import SwiftAtproto

// Vectors for the permissioned-data form of an AT URI, taken from the reference implementation's
// unit tests (packages/syntax/tests/aturi-string.test.ts at the pinned alpha commit). The upstream
// interop fixture files carry no space entries, so `ATURIInteropTests` stays as it is and these
// live on their own.
struct ATURISpaceTests {
  static let spaceRefURI = "at://did:plc:asdf123/space/com.example.group/default"
  static let recordURI =
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/com.atproto.feed.post/abc123"
  static let publicURI = "at://did:plc:asdf123/com.atproto.feed.post/abc123"

  static let validSpaceURIs = [
    // a space reference: authority / marker / type / skey
    spaceRefURI,
    // a record within a space
    recordURI,
    // skey carries the same syntax as a record key
    "at://did:plc:asdf123/space/com.example.group/self",
    "at://did:plc:asdf123/space/com.example.group/3jui7kd54zh2y",
    "at://did:plc:asdf123/space/com.example.group/a.b-c_d~e:f",
    // fragments attach to either form
    "at://did:plc:asdf123/space/com.example.group/default#/frag",
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/com.atproto.feed.post/abc#/frag",
  ]

  static let invalidSpaceURIs = [
    // the space type must be an NSID
    "at://did:plc:asdf123/space/short/default",
    // a space is keyed on DIDs, so a handle is not allowed in either DID position
    "at://user.bsky.social/space/com.example.group/default",
    "at://did:plc:asdf123/space/com.example.group/default/user.bsky.social/com.atproto.feed.post/abc123",
    // the record collection must be an NSID
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/short/abc123",
    // too few segments: the space type and the space key are both mandatory
    "at://did:plc:asdf123/space",
    "at://did:plc:asdf123/space/com.example.group",
    "at://did:plc:asdf123/space/com.example.group/",
    // the record triple is all-or-nothing
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1",
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/com.atproto.feed.post",
    // too many segments
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/com.atproto.feed.post/abc/x",
    // record-key rules apply to the space key
    "at://did:plc:asdf123/space/com.example.group/.",
    "at://did:plc:asdf123/space/com.example.group/..",
    // a space character is rejected before any component validator runs
    "at://not a did/space/com.example.group/default",
    // fragments follow the same JSON Pointer rules as on a public URI
    "at://did:plc:asdf123/space/com.example.group/default#",
    "at://did:plc:asdf123/space/com.example.group/default#/a#/b",
  ]

  @Test(arguments: validSpaceURIs)
  func validParses(_ uri: String) throws {
    let parsed = try ATURI(string: uri)
    #expect(parsed.rawValue == uri)
    #expect(parsed.isSpace)
  }

  @Test(arguments: invalidSpaceURIs)
  func invalidThrows(_ uri: String) {
    #expect(throws: (any Error).self) { try ATURI(string: uri) }
  }

  @Test func overlongSpaceKeyIsRejected() {
    let uri = "at://did:plc:asdf123/space/com.example.group/\(String(repeating: "x", count: 513))"
    #expect(throws: (any Error).self) { try ATURI(string: uri) }
  }

  // MARK: discriminating space from public

  // The marker has to match exactly. A collection NSID always carries at least two dots, so the
  // two forms can never be confused — but a near miss is read as a public URI and then fails the
  // collection validator rather than being treated as a malformed space URI.
  @Test func markerMatchesExactly() throws {
    #expect(throws: (any Error).self) { try ATURI(string: "at://did:plc:asdf123/spacey/x/y") }
    #expect(try !ATURI(string: Self.publicURI).isSpace)
    #expect(try !ATURI(string: "at://did:plc:asdf123").isSpace)
  }

  @Test func spaceAccessorsAreNilOnAPublicURI() throws {
    let uri = try ATURI(string: Self.publicURI)
    #expect(uri.spaceDid == nil)
    #expect(uri.spaceType == nil)
    #expect(uri.skey == nil)
    #expect(uri.spaceRef == nil)
  }

  // MARK: reading a record

  // collection / rkey / authorDid name the record, so they read the same way for both forms.
  @Test func readsARecordFromASpaceURI() throws {
    let uri = try ATURI(string: Self.recordURI)
    // the record's collection, not the `space` marker
    #expect(uri.collection?.rawValue == "com.atproto.feed.post")
    #expect(uri.rkey?.rawValue == "abc123")
    // the record's author, not the space's authority
    #expect(uri.authorDid?.rawValue == "did:plc:user1")
    #expect(uri.spaceDid?.rawValue == "did:plc:asdf123")
  }

  @Test func readsARecordFromAPublicURI() throws {
    let uri = try ATURI(string: Self.publicURI)
    #expect(uri.collection?.rawValue == "com.atproto.feed.post")
    #expect(uri.rkey?.rawValue == "abc123")
    #expect(uri.authorDid?.rawValue == "did:plc:asdf123")
  }

  @Test func aSpaceURIWithNoRecordPathNamesNoRecord() throws {
    let uri = try ATURI(string: Self.spaceRefURI)
    #expect(uri.collection == nil)
    #expect(uri.rkey == nil)
    #expect(uri.authorDid == nil)
  }

  @Test func aPublicURIWithAHandleAuthorityHasNoAuthorDID() throws {
    let uri = try ATURI(string: "at://user.bsky.social/com.atproto.feed.post/abc")
    #expect(uri.authorDid == nil)
    #expect(uri.collection?.rawValue == "com.atproto.feed.post")
  }

  // MARK: reading a space

  @Test func exposesTheSpaceParts() throws {
    let uri = try ATURI(string: Self.spaceRefURI)
    #expect(uri.spaceDid?.rawValue == "did:plc:asdf123")
    #expect(uri.spaceType?.rawValue == "com.example.group")
    #expect(uri.skey?.rawValue == "default")
  }

  // A record URI belongs to a space, so it names one — the record tail is dropped.
  @Test func aRecordURINamesTheSpaceItBelongsTo() throws {
    let uri = try ATURI(string: Self.recordURI)
    #expect(uri.spaceRef?.rawValue == Self.spaceRefURI)
  }

  @Test func aSpaceRefURIYieldsTheSameRefItSpells() throws {
    let uri = try ATURI(string: Self.spaceRefURI)
    let ref = try #require(uri.spaceRef)
    #expect(ref.rawValue == Self.spaceRefURI)
    #expect(ref.spaceDid.rawValue == "did:plc:asdf123")
    #expect(ref.spaceType.rawValue == "com.example.group")
    #expect(ref.skey.rawValue == "default")
  }

  // The ref is composed from the parsed segments, so a fragment on the URI does not leak into it.
  @Test func aFragmentDoesNotLeakIntoTheSpaceRef() throws {
    let uri = try ATURI(string: "\(Self.spaceRefURI)#/frag")
    #expect(uri.spaceRef?.rawValue == Self.spaceRefURI)
    #expect(uri.fragment == "/frag")
  }

  // MARK: composing

  @Test func composesASpaceURIFromARef() throws {
    let ref = try SpaceRef(string: Self.spaceRefURI)
    let uri = try ATURI(spaceRef: ref)
    #expect(uri.rawValue == Self.spaceRefURI)
    #expect(uri.isSpace)
    #expect(uri.collection == nil)
  }

  @Test func composesARecordURIFromARef() throws {
    let ref = try SpaceRef(string: Self.spaceRefURI)
    let uri = try ATURI(
      spaceRef: ref,
      authorDid: try DID(string: "did:plc:user1"),
      collection: try NSID(string: "com.atproto.feed.post"),
      rkey: try RecordKey(string: "abc123")
    )
    #expect(uri.rawValue == Self.recordURI)
    #expect(uri.spaceRef?.rawValue == Self.spaceRefURI)
  }

  // Parsing a composed URI yields the ref it was composed from.
  @Test func composingAndParsingRoundTrip() throws {
    let ref = try SpaceRef(string: Self.spaceRefURI)
    let uri = try ATURI(
      spaceRef: ref,
      authorDid: try DID(string: "did:plc:user1"),
      collection: try NSID(string: "com.atproto.feed.post"),
      rkey: try RecordKey(string: "abc123")
    )
    #expect(try ATURI(string: uri.rawValue).spaceRef == ref)
  }

  // `SpaceRef` also admits explicitly lenient record keys, which do not satisfy the strict wire
  // format the composing initializer parses through.
  @Test func composingRejectsALenientSpaceKey() throws {
    let lenientKey = try RecordKey(string: String(repeating: "x", count: 513), strict: false)
    let ref = try SpaceRef(
      string: "at://did:plc:asdf123/space/com.example.group/\(lenientKey.rawValue)", strict: false)
    #expect(throws: LexiconStringFormatError.self) { try ATURI(spaceRef: ref) }
  }

  // MARK: lenient parsing

  @Test(arguments: [
    "at://did:plc:asdf123/space/com.example.group/default/",
    "at://did:plc:asdf123/space/com.example.group/default?foo=bar",
    "at://did:plc:asdf123/space/com.example.group/default/did:plc:user1/com.atproto.feed.post/%%%",
  ])
  func strictRejectsAndLenientAccepts(_ wire: String) throws {
    #expect(throws: (any Error).self) { try ATURI(string: wire, strict: true) }
    let uri = try ATURI(string: wire, strict: false)
    #expect(uri.rawValue == wire)
    #expect(uri.isSpace)
  }

  @Test func lenientRelaxesTheSpaceKeyTheSameWayItRelaxesARecordKey() throws {
    let wire = "at://did:plc:asdf123/space/com.example.group/\(String(repeating: "x", count: 513))"
    #expect(throws: (any Error).self) { try ATURI(string: wire, strict: true) }
    let uri = try ATURI(string: wire, strict: false)
    #expect(uri.skey?.rawValue == String(repeating: "x", count: 513))
  }

  // The authority and the space type are validated in both modes, matching where the space URI
  // grammar places each check.
  @Test(arguments: [
    "at://user.bsky.social/space/com.example.group/default",
    "at://did:plc:asdf123/space/short/default",
  ])
  func lenientDoesNotRelaxTheAuthorityOrTheSpaceType(_ wire: String) {
    #expect(throws: (any Error).self) { try ATURI(string: wire, strict: false) }
  }
}
