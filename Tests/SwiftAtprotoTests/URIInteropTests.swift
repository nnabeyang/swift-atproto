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

  static let invalidURIs: [String] = [
    // Empty / colon-only / scheme-only.
    "", ":", "https:", "at:", "at://",
    // Scheme missing (no colon).
    "example.com", "/path", "/", "//host/path",
    // Scheme starts with non-ALPHA (digit, +, -, .).
    "1http://example.com", "+http://example.com", "-http://example.com", ".http://example.com",
    // Scheme contains underscore (RFC 3986 §3.1 disallows).
    "ht_tp://example.com",
    // Whitespace anywhere in body.
    "https://example.com/ space", "https://example.com\twith\ttab",
    // ASCII control characters in body.
    "https://example.com\u{0001}body", "https://example.com\nbody",
    // CR/LF/NUL.
    "https://example.com\r", "https://example.com\u{0000}",
    // DEL (0x7F).
    "https://example.com\u{007F}",
    // Empty body after "//".
    "https://", "wss://",
    // Pure whitespace.
    " ", "\t",
  ]

  @Test(arguments: invalidURIs)
  func invalidThrows(_ uri: String) {
    #expect(throws: (any Error).self) { try URI(string: uri) }
  }

  @Test func acceptsExactly8KiBInput() throws {
    // scheme(5 byte "https") + ":" + body of 8186 byte → total 8 * 1024 = 8192 byte (cap).
    let body = String(repeating: "a", count: 8 * 1024 - 6)
    let uri = "https:" + body
    let u = try URI(string: uri)
    #expect(u.rawValue.utf8.count == 8 * 1024)
    #expect(u.scheme == "https")
  }

  @Test func rejectsOver8KiBInput() {
    // Just past the cap.
    let body = String(repeating: "a", count: 8 * 1024 - 5)
    let uri = "https:" + body
    #expect(uri.utf8.count == 8 * 1024 + 1)
    #expect(throws: (any Error).self) { try URI(string: uri) }
  }

  // MARK: derived accessors

  @Test func urlAccessorReturnsNilForAtURIWithDID() throws {
    // `URL(string:)` returns nil for `at://did:plc:*` (the embedded `:` in the authority
    // interacts with port grammar). The wire string is preserved in `rawValue`. The result
    // is nil in either `encodingInvalidCharacters` mode.
    let u = try URI(string: "at://did:plc:abc")
    #expect(u.url() == nil)
    #expect(u.url(encodingInvalidCharacters: false) == nil)
    #expect(u.rawValue == "at://did:plc:abc")
  }

  @Test func urlAccessorReturnsValueForHttpsScheme() throws {
    // Assert non-nil + scheme match rather than full `absoluteString` equality so the test
    // survives any URL canonicalization changes across OS versions.
    let u = try URI(string: "https://example.com/path")
    #expect(u.url() != nil)
    #expect(u.url()?.scheme == "https")
  }

  @Test func urlAccessorReturnsNonNilForEmptyAuthority() throws {
    // `https:///x` is RFC 3986 valid (empty authority + path-abempty) and `URL(string:)`
    // returns a non-nil URL. The contract is wire-shape correctness — non-nil here does NOT
    // imply the URL is loadable: `URLSession` would fail because there is no host.
    let u = try URI(string: "https:///x")
    #expect(u.url() != nil)
    #expect(u.url()?.host(percentEncoded: false) == nil)
  }

  @Test func urlAccessorIDNBehaviorByEncodingMode() throws {
    // Default (`encodingInvalidCharacters: true`): Foundation silently re-encodes IDN to
    // punycode, so `.url()` is non-nil and `absoluteString` diverges from `rawValue`.
    // Strict (`encodingInvalidCharacters: false`): wire-faithful — nil because the wire form
    // would require canonicalization. The wire string is preserved in `.rawValue` either way.
    let u = try URI(string: "https://例え.テスト/foo")
    #expect(u.rawValue == "https://例え.テスト/foo")
    // Default mode: punycode-canonicalized URL.
    #expect(u.url() != nil)
    #expect(u.url()?.absoluteString.contains("xn--") == true)
    // Strict mode: nil.
    #expect(u.url(encodingInvalidCharacters: false) == nil)
  }

  @Test func urlAccessorAcceptsDIDColonScheme() throws {
    // `URL(string:)` accepts `did:plc:abc` as an opaque, no-authority URI; `.url()` is non-nil.
    // Asserting non-nil (rather than full `absoluteString` equality) survives canonicalization
    // changes in `URL`. Note: if `URL(string:)` ever rejects `did:` URIs outright, this test
    // will fail — intentionally, since we want to be notified of that behavior change.
    let u = try URI(string: "did:plc:abc")
    #expect(u.url() != nil)
  }

  @Test func urlAccessorAcceptsFileSchemeForms() throws {
    // Both `path-absolute` (`file:/etc/hosts`) and empty-authority (`file:///etc/hosts`)
    // forms yield a non-nil URL. Pin this so a future tightening of `URL(string:)` is caught.
    let u1 = try URI(string: "file:/etc/hosts")
    #expect(u1.url() != nil)
    let u2 = try URI(string: "file:///etc/hosts")
    #expect(u2.url() != nil)
  }

  @Test func atUriAccessorReturnsValueForValidATURI() throws {
    let u = try URI(string: "at://did:plc:abc/com.example.foo/rkey")
    #expect(u.atUri != nil)
    #expect(u.atUri?.rawValue == "at://did:plc:abc/com.example.foo/rkey")
    #expect(u.atUri?.collection?.rawValue == "com.example.foo")
    #expect(u.atUri?.rkey?.rawValue == "rkey")
  }

  @Test func atUriAccessorReturnsValueForHandleOnlyAuthority() throws {
    // ATURI's restricted form permits authority alone (collection/rkey optional).
    let u = try URI(string: "at://example.com")
    #expect(u.atUri != nil)
    #expect(u.atUri?.authority.rawValue == "example.com")
    #expect(u.atUri?.collection == nil)
    #expect(u.atUri?.rkey == nil)
  }

  @Test func atUriAccessorReturnsNilForNonATScheme() throws {
    let u = try URI(string: "https://example.com")
    #expect(u.atUri == nil)
  }

  @Test func atUriAccessorReturnsNilForAtSchemeWithoutDoubleSlash() throws {
    // `at:/` and `at:/x` are valid `uri` (path-absolute) but the strict AT URI parser
    // requires the `at://` prefix, so `.atUri` is nil.
    let u1 = try URI(string: "at:/")
    #expect(u1.atUri == nil)
    let u2 = try URI(string: "at:/x")
    #expect(u2.atUri == nil)
  }

  @Test func atUriAccessorReturnsNilForMalformedATURI() throws {
    // Wire-shape valid for `uri` but not a valid restricted-form AT URI (path lacks NSID).
    let u = try URI(string: "at://example.com/not-an-nsid")
    #expect(u.atUri == nil)
  }

  // MARK: kind classification

  @Test func atHandleAuthorityClassifiesAsAturl() throws {
    let uri = try URI(string: "at://example.com")
    #expect(uri.kind == .aturl)
  }

  @Test func atDIDAuthorityClassifiesAsAturl() throws {
    let uri = try URI(string: "at://did:plc:abc/com.example.foo/rkey")
    #expect(uri.kind == .aturl)
  }

  @Test func atPathAbsoluteFallsBackToUrl() throws {
    // `at:/` is a valid lexicon `uri` (path-absolute) but not a valid ATURI → URL fallback.
    let uri = try URI(string: "at:/")
    #expect(uri.kind == .url)
  }

  @Test func atPathAbsoluteWithBodyFallsBackToUrl() throws {
    let uri = try URI(string: "at:/x")
    #expect(uri.kind == .url)
  }

  @Test func httpsClassifiesAsUrl() throws {
    let uri = try URI(string: "https://example.com/path")
    #expect(uri.kind == .url)
  }

  @Test func fileClassifiesAsUrl() throws {
    let uri = try URI(string: "file:///etc/hosts")
    #expect(uri.kind == .url)
  }

  @Test func didOpaqueClassifiesAsUrl() throws {
    let uri = try URI(string: "did:plc:abc")
    #expect(uri.kind == .url)
  }

  @Test func dataClassifiesAsUrl() throws {
    let uri = try URI(string: "data:text/plain,Hello")
    #expect(uri.kind == .url)
  }

  @Test func bothParsersFailingClassifiesAsOther() throws {
    // `at://example.com:notaport` is wire-shape valid (`uri` accepts the body) but:
    //   - ATURI rejects because authority `example.com:notaport` is neither a valid DID nor a
    //     valid handle (the `:` inside a single label breaks the handle grammar)
    //   - URL(string:) returns nil due to port grammar (`:` must be followed by digits)
    // → classify falls through to `.other`.
    let uri = try URI(string: "at://example.com:notaport")
    #expect(uri.kind == .other)
  }
}
