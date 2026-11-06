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

  // Generic arguments become a clause of their own, so a qualified argument
  // isn't cut on its dots together with the base.
  func testTypeSyntaxParsesGenericArguments() throws {
    let qualified = Lex.typeSyntax("SwiftAtproto.FormatString<SwiftAtproto.DID>")
    XCTAssertEqual(qualified.description, "SwiftAtproto.FormatString<SwiftAtproto.DID>")
    let member = try XCTUnwrap(qualified.as(MemberTypeSyntax.self))
    XCTAssertEqual(member.name.text, "FormatString")
    let argument = try XCTUnwrap(member.genericArgumentClause?.arguments.first)
    XCTAssertEqual(argument.trimmedDescription, "SwiftAtproto.DID")

    let plain = try XCTUnwrap(Lex.typeSyntax("FormatString<DID>").as(IdentifierTypeSyntax.self))
    XCTAssertEqual(plain.name.text, "FormatString")
    XCTAssertEqual(plain.genericArgumentClause?.arguments.count, 1)

    XCTAssertEqual(
      Lex.typeSyntax("[SwiftAtproto.FormatString<SwiftAtproto.DID>]").description,
      "[SwiftAtproto.FormatString<SwiftAtproto.DID>]")
    // A comma nested in an argument stays with that argument.
    let nested = try XCTUnwrap(Lex.typeSyntax("A<[B<C, E>], D>").as(IdentifierTypeSyntax.self))
    let arguments = try XCTUnwrap(nested.genericArgumentClause?.arguments)
    XCTAssertEqual(arguments.map { $0.argument.trimmedDescription }, ["[B<C,E>]", "D"])
  }

  func testRefExprParsesGenericArgumentsAndArrays() throws {
    let generic = Lex.refExpr("SwiftAtproto.FormatString<SwiftAtproto.DID>")
    XCTAssertEqual(generic.description, "SwiftAtproto.FormatString<SwiftAtproto.DID>")
    XCTAssertNotNil(generic.as(GenericSpecializationExprSyntax.self))

    let array = Lex.refExpr("[SwiftAtproto.FormatString<SwiftAtproto.DID>]")
    XCTAssertEqual(array.description, "[SwiftAtproto.FormatString<SwiftAtproto.DID>]")
    XCTAssertNotNil(array.as(ArrayExprSyntax.self))
  }

  func testRefExpr() {
    XCTAssertEqual(Lex.refExpr("App.Type").description, "App.`Type`")
    XCTAssertEqual(Lex.refExpr("default").description, "`default`")
  }
}
