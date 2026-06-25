import Foundation
import Testing

@testable import SwiftAtproto

// Valid/invalid AT URI vectors for the restricted (Lexicon) syntax in strict mode
// (AT URI spec: https://atproto.com/specs/at-uri-scheme). `\u{20}` marks significant spaces.
struct ATURIInteropTests {
  // The "at://" + "did:plc:asdf123" + "/" + "com.atproto.feed.post" + "/" prefix is 43 chars.
  static let recordPrefix = "at://did:plc:asdf123/com.atproto.feed.post/"

  static let validATURIs: [String] = [
    "at://did:plc:asdf123",
    "at://user.bsky.social",
    "at://did:plc:asdf123/com.atproto.feed.post",
    "at://did:plc:asdf123/com.atproto.feed.post/record",
    "at://did:plc:asdf123/com.atproto.feed.post/asdf123",
    "at://did:plc:asdf123/com.atproto.feed.post/a",
    "at://did:plc:asdf123/com.atproto.feed.post/asdf-123",
    "at://did:abc:123",
    "at://did:abc:123/io.nsid.someFunc/record-key",
    "at://did:abc:123/io.nsid.someFunc/self.",
    "at://did:abc:123/io.nsid.someFunc/lang:",
    "at://did:abc:123/io.nsid.someFunc/:",
    "at://did:abc:123/io.nsid.someFunc/-",
    "at://did:abc:123/io.nsid.someFunc/_",
    "at://did:abc:123/io.nsid.someFunc/~",
    "at://did:abc:123/io.nsid.someFunc/...",
    "at://did:plc:asdf123/com.atproto.feed.postV2",
    // 512-char record key (the maximum allowed length).
    recordPrefix + String(repeating: "o", count: 512),
  ]

  static let invalidATURIs: [String] = [
    "a://did:plc:asdf123",
    "at//did:plc:asdf123",
    "at:/a/did:plc:asdf123",
    "at:/did:plc:asdf123",
    "AT://did:plc:asdf123",
    "http://did:plc:asdf123",
    "://did:plc:asdf123",
    "at:did:plc:asdf123",
    "at:///did:plc:asdf123",
    "at://:/did:plc:asdf123",
    "at:/\u{20}/did:plc:asdf123",
    "at://did:plc:asdf123\u{20}",
    "at://did:plc:asdf123/\u{20}",
    "\u{20}at://did:plc:asdf123",
    "at://did:plc:asdf123/com.atproto.feed.post\u{20}",
    "at://did:plc:asdf123/com.atproto.feed.post#\u{20}",
    "at://did:plc:asdf123/com.atproto.feed.post#/\u{20}",
    "at://did:plc:asdf123/com.atproto.feed.post#/frag\u{20}",
    "at://did:plc:asdf123/com.atproto.feed.post#fr\u{20}ag",
    "at://name",
    "at://name.0",
    "at://diD:plc:asdf123",
    "at://did:plc:asdf123/com.atproto.feed.p@st",
    "at://did:plc:asdf123/com.atproto.feed.p$st",
    "at://did:plc:asdf123/com.atproto.feed.p%st",
    "at://did:plc:asdf123/com.atproto.feed.p&st",
    "at://did:plc:asdf123/com.atproto.feed.p()t",
    "at://did:plc:asdf123/com.atproto.feed_post",
    "at://did:plc:asdf123/-com.atproto.feed.post",
    "at://did:plc:asdf@123/com.atproto.feed.post",
    "at://DID:plc:asdf123",
    "at://user.bsky.123",
    "at://bsky",
    "at://did:plc:",
    "at://frag",
    // Exceeds the 8 KB overall limit.
    recordPrefix + String(repeating: "o", count: 8200),
    "at://user.bsky.social//",
    "at://user.bsky.social//com.atproto.feed.post",
    "at://user.bsky.social/com.atproto.feed.post//",
    "at://did:plc:asdf123/com.atproto.feed.post/asdf123/more/more',",
    "at://did:plc:asdf123/short/stuff",
    "at://did:plc:asdf123/12345",
    "at://did:plc:asdf123/",
    "at://user.bsky.social/",
    "at://did:plc:asdf123/com.atproto.feed.post/",
    "at://did:plc:asdf123/com.atproto.feed.post/record/",
    "at://did:plc:asdf123/com.atproto.feed.post/record/#/frag",
    "at://did:plc:asdf123/com.atproto.feed.post/asdf123/asdf",
    "at://did:plc:asdf123#",
    "at://did:plc:asdf123##",
    "at://did:plc:asdf123#/asdf#/asdf",
    "at://did:plc:asdf123/com.atproto.feed.post/%23",
    "at://did:plc:asdf123/com.atproto.feed.post/$@!*)(:,;~.sdf123",
    "at://did:plc:asdf123/com.atproto.feed.post/~'sdf123\")",
    "at://did:plc:asdf123/com.atproto.feed.post/$",
    "at://did:plc:asdf123/com.atproto.feed.post/@",
    "at://did:plc:asdf123/com.atproto.feed.post/!",
    "at://did:plc:asdf123/com.atproto.feed.post/*",
    "at://did:plc:asdf123/com.atproto.feed.post/(",
    "at://did:plc:asdf123/com.atproto.feed.post/,",
    "at://did:plc:asdf123/com.atproto.feed.post/;",
    "at://did:plc:asdf123/com.atproto.feed.post/abc%30123",
    "at://did:plc:asdf123/com.atproto.feed.post/%30",
    "at://did:plc:asdf123/com.atproto.feed.post/%3",
    "at://did:plc:asdf123/com.atproto.feed.post/%",
    "at://did:plc:asdf123/com.atproto.feed.post/%zz",
    "at://did:plc:asdf123/com.atproto.feed.post/%%%",
    "at://did:plc:asdf123/com.atproto.feed.post/.",
    "at://did:plc:asdf123/com.atproto.feed.post/..",
  ]

  @Test(arguments: validATURIs)
  func validParses(_ uri: String) throws {
    _ = try ATURI(string: uri)
  }

  @Test(arguments: invalidATURIs)
  func invalidThrows(_ uri: String) {
    #expect(throws: (any Error).self) { try ATURI(string: uri) }
  }

  @Test func parsesComponents() throws {
    let full = try ATURI(string: "at://did:plc:asdf123/com.atproto.feed.post/3jui7kd54zh2y")
    #expect(full.authority == "did:plc:asdf123")
    #expect(full.collection == "com.atproto.feed.post")
    #expect(full.rkey == "3jui7kd54zh2y")
    #expect(full.fragment == nil)

    let handleOnly = try ATURI(string: "at://user.bsky.social")
    #expect(handleOnly.authority == "user.bsky.social")
    #expect(handleOnly.collection == nil)
    #expect(handleOnly.rkey == nil)

    let collectionOnly = try ATURI(string: "at://did:plc:asdf123/com.atproto.feed.post")
    #expect(collectionOnly.collection == "com.atproto.feed.post")
    #expect(collectionOnly.rkey == nil)
  }

  @Test func queryIsRejectedInStrict() {
    #expect(throws: (any Error).self) { try ATURI(string: "at://did:plc:asdf123?foo=bar") }
  }

  @Test func jsonPointerFragmentIsAccepted() throws {
    let uri = try ATURI(string: "at://did:plc:asdf123/com.atproto.feed.post/record#/text")
    #expect(uri.fragment == "/text")
    #expect(uri.rkey == "record")
  }
}
