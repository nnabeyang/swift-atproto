import SwiftSyntax
import XCTest

@testable import SwiftAtprotoLex

final class KeywordEscapingTests: XCTestCase {
  func testEscapedSwiftKeyword() {
    XCTAssertEqual("default".escapedSwiftKeyword, "`default`")
    XCTAssertEqual("in".escapedSwiftKeyword, "`in`")
    XCTAssertEqual("Type".escapedSwiftKeyword, "`Type`")
    XCTAssertEqual("foo".escapedSwiftKeyword, "foo")
    XCTAssertEqual("async".escapedSwiftKeyword, "async")
  }

  func testLexIdentifier() {
    XCTAssertEqual(TokenSyntax.lexIdentifier("default").text, "`default`")
    XCTAssertEqual(TokenSyntax.lexIdentifier("foo").text, "foo")
  }

  // Call labels are backquoted only where Swift requires it, so that the
  // generated calls compile without the "does not need to be escaped" warning.
  func testLexArgumentLabel() {
    XCTAssertEqual(TokenSyntax.lexArgumentLabel("default").text, "default")
    XCTAssertEqual(TokenSyntax.lexArgumentLabel("Type").text, "Type")
    XCTAssertEqual(TokenSyntax.lexArgumentLabel("self").text, "self")
    XCTAssertEqual(TokenSyntax.lexArgumentLabel("inout").text, "`inout`")
    XCTAssertEqual(TokenSyntax.lexArgumentLabel("0040000").text, "_0040000")
    XCTAssertEqual(TokenSyntax.lexArgumentLabel("ordinary").text, "ordinary")
  }

  func testTypeSyntax() {
    XCTAssertEqual(Lex.typeSyntax("App.Bsky.Foo").description, "App.Bsky.Foo")
    XCTAssertEqual(Lex.typeSyntax("App.Type.Foo").description, "App.`Type`.Foo")
    XCTAssertEqual(Lex.typeSyntax("[App.Type]").description, "[App.`Type`]")
    XCTAssertEqual(Lex.typeSyntax("default").description, "`default`")
    XCTAssertEqual(Lex.typeSyntax("String").description, "String")
  }

  func testRefExpr() {
    XCTAssertEqual(Lex.refExpr("App.Type").description, "App.`Type`")
    XCTAssertEqual(Lex.refExpr("default").description, "`default`")
  }
}
