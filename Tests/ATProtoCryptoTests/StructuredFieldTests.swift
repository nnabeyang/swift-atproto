import Foundation
import Testing

@testable import ATProtoCrypto

struct StructuredFieldTests {
  // Values whose serialization is already canonical, so they round-trip
  // unchanged. Several are examples from RFC 9651 and RFC 9421.
  @Test(arguments: [
    "en=\"Applepie\", da=:w4ZibGV0w6ZydGUK:",
    "a=?0, b, c;foo=bar",
    "rating=1.5, feelings=(joy sadness)",
    "a=(1 2), b=3, c=4;aa=bb, d=(5 6);valid",
    "sig1=(\"@method\" \"@authority\" \"@path\" \"content-digest\");created=1618884473;keyid=\"test-key-rsa-pss\"",
    "mac=(\"atproto-space-commit\";sf);keyid=\"did:key:zDnaX\";tag=\"atproto-space-commit\"",
    "ver=1, repo=\"did:example:alice\", data=:AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=:",
    "t=foo/bar:baz, n=-12, d=-0.25, e=@1659578233, s=\"a\\\"b\\\\c\", ds=%\"f%c3%bc%25%22\"",
    "x=()",
  ])
  func roundTripsCanonicalValues(value: String) throws {
    let dictionary = try #require(StructuredDictionary.parse(value))
    #expect(dictionary.serialized == value)
  }

  // RFC 9421 §2.1.1 signs an `sf` field in this normalized form.
  @Test(arguments: [
    ("  a=1 ,\tb=2  ", "a=1, b=2"),
    ("a=:AAEC:", "a=:AAEC:"),
    ("a=:AAE:", "a=:AAE=:"),
    ("a=1, b=2, a=3", "a=3, b=2"),
    ("a=1;x=1;y=2;x=3", "a=1;x=3;y=2"),
    ("a=?1;p", "a;p"),
    ("a=(  1   2  );q", "a=(1 2);q"),
    ("a=1.50, b=2.000, c=0.1", "a=1.5, b=2.0, c=0.1"),
    ("a; b=?1", "a;b"),
    ("", ""),
  ])
  func normalizes(value: String, canonical: String) throws {
    #expect(try #require(StructuredDictionary.parse(value)).serialized == canonical)
  }

  @Test func keepsParametersAndInnerListItems() throws {
    let dictionary = try #require(
      StructuredDictionary.parse("mac=(\"atproto-space-commit\";sf);keyid=\"did:key:zDnaX\";tag=\"t\""))
    guard case .innerList(let list) = dictionary["mac"] else {
      Issue.record("not an inner list")
      return
    }
    #expect(list.items == [StructuredItem(.string("atproto-space-commit"), parameters: .init([("sf", .boolean(true))]))])
    #expect(list.parameters.keys == ["keyid", "tag"])
    #expect(list.parameters["keyid"] == .string("did:key:zDnaX"))
    #expect(list.parameters["tag"] == .string("t"))
  }

  @Test func readsEachKindOfBareItem() throws {
    let dictionary = try #require(
      StructuredDictionary.parse(
        "i=42, d=4.5, s=\"x\", t=tok, b=:AQI=:, f=?0, at=@-1, ds=%\"%e2%82%ac\""))
    let expected: [(String, StructuredBareItem)] = [
      ("i", .integer(42)), ("d", .decimal(thousandths: 4500)), ("s", .string("x")),
      ("t", .token("tok")), ("b", .bytes(Data([1, 2]))), ("f", .boolean(false)),
      ("at", .date(-1)), ("ds", .displayString("€")),
    ]
    for (key, item) in expected {
      #expect(dictionary[key] == .item(StructuredItem(item)))
    }
  }

  @Test(arguments: [
    "a=", "A=1", "a=1,", "a=1,,b=2", "a=1 b=2", "a=\"unterminated", "a=\"\\x\"",
    "a=1234567890123456", "a=1234567890123.1", "a=1.2345", "a=1.", "a=-", "a=?2",
    "a=:AA==", "a=:A#A=:", "a=(1 2", "a=(1,2)", "a=@1.5", "a=%\"%C3%BC\"", "a=%\"%c3\"",
    "a=%x", "a=1;", "a=1;B", "a=\u{7f}",
  ])
  func rejectsMalformedValues(value: String) {
    #expect(StructuredDictionary.parse(value) == nil)
  }
}
