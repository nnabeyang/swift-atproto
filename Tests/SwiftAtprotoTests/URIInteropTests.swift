import Foundation
import Testing

@testable import SwiftAtproto

// Valid/invalid wire-shape vectors for the lenient `uri` string format parser. The `rawValue`
// is always preserved verbatim; the parsed `scheme` keeps its wire case.
struct URIInteropTests {
  static let validURIs: [String] = [
    // AT Protocol URIs.
    "at://did:plc:abc",
    "at://did:plc:abc/com.example.foo",
    "at://did:plc:abc/com.example.foo/rkey",
    "at://example.com",
    // HTTP / HTTPS.
    "https://example.com",
    "http://example.com",
    "https://example.com/path/to/resource",
    "https://example.com/path?query=value&other=1",
    "https://example.com/path#fragment",
    "https://example.com:8443/path",
    // WebSocket schemes.
    "wss://relay.example.com",
    "ws://localhost:9000/feed",
    // Schemes without authority (no `//`).
    "did:plc:abc123",
    "did:web:example.com",
    "data:text/plain,Hello",
    "tel:+1-555-0100",
    "mailto:user@example.com",
    // RFC 3986 §3 `path-absolute` hier-part (scheme followed by absolute path, no authority).
    "file:/etc/hosts", "at:/", "at:/x", "https:/x",
    // RFC 3986 §3.2 empty authority + path-abempty (`scheme://` followed by absolute path).
    "file:///etc/hosts", "https:///x", "at:///x/y",
    // `//` after the authority delimiter is consumed only once; the remaining bytes form the
    // body and are accepted verbatim (no further interpretation by this parser).
    "https:////host",
    // IPFS / DNS / other examples cited by the atproto spec.
    "ipfs://QmHash123",
    "dns://_atproto.example.com",
    // Scheme case preserved (uppercase scheme is grammar-legal per RFC 3986).
    "HTTPS://Example.Com",
    "AT://Did:Plc:ABC",
    // Scheme characters: ALPHA / DIGIT / "+" / "-" / "."
    "x-custom:body",
    "git+ssh://git@example.com/repo.git",
    "z39.50r://library.example.com",
    "h2://example.com",
    // Non-ASCII bytes are accepted verbatim in the body (verbatim wire preservation).
    "https://例え.テスト/foo",
    // Very short minimal forms.
    "a:b",
    "ab://c",
  ]

  @Test(arguments: validURIs)
  func validParses(_ uri: String) throws {
    let value = try URI(string: uri)
    #expect(value.rawValue == uri)
    #expect(!value.scheme.isEmpty)
  }

  @Test func parsesSchemeForAtUri() throws {
    let u = try URI(string: "at://did:plc:abc/com.example.foo/rkey")
    #expect(u.scheme == "at")
    #expect(u.rawValue == "at://did:plc:abc/com.example.foo/rkey")
  }

  @Test func parsesSchemeForHttps() throws {
    let u = try URI(string: "https://example.com/path?q=1#frag")
    #expect(u.scheme == "https")
  }

  @Test func parsesSchemeWithoutAuthority() throws {
    let u = try URI(string: "did:plc:abc")
    #expect(u.scheme == "did")
    #expect(u.rawValue == "did:plc:abc")
  }

  @Test func preservesSchemeCaseVerbatim() throws {
    let u = try URI(string: "HTTPS://Example.Com")
    #expect(u.scheme == "HTTPS")
    #expect(u.rawValue == "HTTPS://Example.Com")
  }

  @Test func parsesSchemeWithSpecialCharacters() throws {
    let u = try URI(string: "git+ssh://git@example.com/repo.git")
    #expect(u.scheme == "git+ssh")
  }
}
