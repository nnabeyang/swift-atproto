import Foundation
import Testing

@testable import SwiftAtproto

// The decoder is deliberately narrow: JOSE writes every segment with the URL-safe alphabet and no
// padding, so anything else is refused rather than repaired.
struct Base64URLTests {
  @Test func decodesTheRFC4648TestVectors() {
    #expect(base64URLDecoded("") == Data())
    #expect(base64URLDecoded("Zg") == Data("f".utf8))
    #expect(base64URLDecoded("Zm8") == Data("fo".utf8))
    #expect(base64URLDecoded("Zm9v") == Data("foo".utf8))
    #expect(base64URLDecoded("Zm9vYg") == Data("foob".utf8))
    #expect(base64URLDecoded("Zm9vYmE") == Data("fooba".utf8))
    #expect(base64URLDecoded("Zm9vYmFy") == Data("foobar".utf8))
  }

  @Test func decodesTheTwoCharactersThatMakeTheAlphabetURLSafe() {
    // The same bytes are `+_8` and `-/8` in the standard alphabet, which is why accepting both
    // alphabets would let one string decode two ways.
    #expect(base64URLDecoded("-_8") == Data([0xFB, 0xFF]))
  }

  @Test func rejectsPadding() {
    #expect(base64URLDecoded("Zg==") == nil)
    #expect(base64URLDecoded("Zm8=") == nil)
  }

  @Test func rejectsTheStandardAlphabet() {
    #expect(base64URLDecoded("+_8") == nil)
    #expect(base64URLDecoded("-/8") == nil)
  }

  @Test func rejectsWhitespace() {
    #expect(base64URLDecoded("Zm 9v") == nil)
    #expect(base64URLDecoded("Zm9v\n") == nil)
    #expect(base64URLDecoded(" Zm9v") == nil)
  }

  @Test func rejectsALengthOfOneModuloFour() {
    // No base64 quantum is one character wide, so such a string encodes nothing.
    #expect(base64URLDecoded("Z") == nil)
    #expect(base64URLDecoded("Zm9vY") == nil)
  }
}
