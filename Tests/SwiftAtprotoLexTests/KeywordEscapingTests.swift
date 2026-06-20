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
