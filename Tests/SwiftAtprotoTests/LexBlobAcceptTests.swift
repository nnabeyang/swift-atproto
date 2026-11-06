import Testing

@testable import SwiftAtproto

@Suite("LexBlob.isAccepted")
struct LexBlobAcceptTests {
  @Test(
    "matching MIME types",
    arguments: [
      ("image/png", ["image/png", "image/jpeg"]),
      ("image/jpeg", ["image/png", "image/jpeg"]),
      ("image/webp", ["image/*"]),
      ("video/mp4", ["*/*"]),
      ("text/vtt", ["image/*", "text/vtt"]),
      // The type and subtype compare without regard to case.
      ("IMAGE/PNG", ["image/png"]),
      ("image/png", ["Image/*"]),
      // Parameters and surrounding whitespace are ignored.
      ("text/vtt; charset=utf-8", ["text/vtt"]),
      (" image/png ", ["image/png"]),
    ])
  func accepted(mimeType: String, accept: [String]) {
    #expect(LexBlob.isAccepted(mimeType: mimeType, by: accept))
  }

  @Test(
    "MIME types that don't match",
    arguments: [
      ("video/mp4", ["image/*"]),
      ("image/gif", ["image/png", "image/jpeg"]),
      ("image", ["image/*"]),
      ("imagery/png", ["image/*"]),
      // Partial globs and a stand-alone wildcard aren't supported.
      ("text/html", ["text/ht*"]),
      ("text/html", ["*"]),
    ])
  func notAccepted(mimeType: String, accept: [String]) {
    #expect(!LexBlob.isAccepted(mimeType: mimeType, by: accept))
  }

  @Test("an empty list accepts any MIME type, like an absent one")
  func emptyList() {
    #expect(LexBlob.isAccepted(mimeType: "application/octet-stream", by: []))
  }
}
