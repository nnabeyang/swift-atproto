import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct SpaceTypeDefinition: Codable {
  let type: FieldType
  let key: String
  let name: String
  let nameLang: [String: String]?
  let collections: [String]
  let description: String?

  private enum CodingKeys: String, CodingKey {
    case type
    case key
    case name
    case nameLang = "name:lang"
    case collections
    case description
  }
}

extension SpaceTypeDefinition: SwiftCodeGeneratable {
  func generateDeclaration(
    leadingTrivia: Trivia? = nil, ts _: TypeSchema, name declName: String, type typeName: String,
    defMap _: ExtDefMap, generate _: GenerateOption
  ) -> any DeclSyntaxProtocol {
    EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .lexIdentifier(declName),
      inheritanceClause: InheritanceClauseSyntax {
        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("LexSpace")))
      }
    ) {
      staticLetDecl(leadingTrivia: .newline, ident: "id", value: StringLiteralExprSyntax(content: typeName))
      Self.typedStaticLet(
        ident: "key",
        type: Lex.typeSyntax("LexRecordKeyType"),
        value: Self.keyExpr(key)
      )
      Self.typedStaticLet(
        ident: "name",
        type: Lex.typeSyntax("Swift.String"),
        value: ExprSyntax(StringLiteralExprSyntax(content: name))
      )
      Self.typedStaticLet(
        ident: "nameLang",
        type: TypeSyntax(
          OptionalTypeSyntax(
            wrappedType: DictionaryTypeSyntax(
              key: Lex.typeSyntax("Swift.String"),
              value: Lex.typeSyntax("Swift.String")
            )
          )
        ),
        value: Self.nameLangExpr(nameLang)
      )
      Self.typedStaticLet(
        ident: "collections",
        type: Lex.typeSyntax("[FormatString<NSID>]"),
        value: Self.collectionsExpr(collections)
      )
      Self.typedStaticLet(
        ident: "description",
        type: TypeSyntax(OptionalTypeSyntax(wrappedType: Lex.typeSyntax("Swift.String"))),
        value: Self.optionalStringExpr(description)
      )
    }
  }

  private static func typedStaticLet(ident: String, type: TypeSyntax, value: some ExprSyntaxProtocol) -> VariableDeclSyntax {
    VariableDeclSyntax(
      leadingTrivia: .newline,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.static)),
      ],
      bindingSpecifier: .keyword(.let)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier(ident)),
        typeAnnotation: TypeAnnotationSyntax(type: type),
        initializer: InitializerClauseSyntax(value: value)
      )
    }
  }

  // The record key vocabulary is open: `literal:<value>` carries a payload and
  // newer Lexicons may add types, so anything outside the three known values
  // goes through the raw-value initializer instead of being dropped.
  private static func keyExpr(_ key: String) -> ExprSyntax {
    switch key {
    case "any", "nsid", "tid":
      ExprSyntax(MemberAccessExprSyntax(name: .identifier(key)))
    default:
      ExprSyntax(
        FunctionCallExprSyntax(
          calledExpression: DeclReferenceExprSyntax(baseName: .identifier("LexRecordKeyType")),
          leftParen: .leftParenToken(),
          arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
              label: .identifier("rawValue"),
              colon: .colonToken(),
              expression: StringLiteralExprSyntax(content: key)
            )
          ]),
          rightParen: .rightParenToken()
        )
      )
    }
  }

  private static func nameLangExpr(_ nameLang: [String: String]?) -> ExprSyntax {
    guard let nameLang, !nameLang.isEmpty else {
      return ExprSyntax(NilLiteralExprSyntax())
    }
    // Sort by language code so the generated source does not depend on the
    // dictionary's iteration order.
    let sorted = nameLang.sorted { $0.key < $1.key }
    return ExprSyntax(
      DictionaryExprSyntax(
        leftSquare: .leftSquareToken(),
        content: .elements(
          DictionaryElementListSyntax {
            for (i, element) in sorted.enumerated() {
              DictionaryElementSyntax(
                leadingTrivia: .newline,
                key: StringLiteralExprSyntax(content: element.key),
                value: StringLiteralExprSyntax(content: element.value),
                trailingComma: i < sorted.count - 1 ? .commaToken() : nil
              )
            }
          }),
        rightSquare: .rightSquareToken(leadingTrivia: .newline)
      )
    )
  }

  private static func collectionsExpr(_ collections: [String]) -> ExprSyntax {
    guard !collections.isEmpty else {
      return ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([])))
    }
    return ExprSyntax(
      ArrayExprSyntax(
        leftSquare: .leftSquareToken(),
        elements: ArrayElementListSyntax {
          for (i, collection) in collections.enumerated() {
            ArrayElementSyntax(
              leadingTrivia: .newline,
              expression: formatStringInit(collection),
              trailingComma: i < collections.count - 1 ? .commaToken() : nil
            )
          }
        },
        rightSquare: .rightSquareToken(leadingTrivia: .newline)
      )
    )
  }

  // `FormatString` keeps the wire string verbatim, so a collection that is not
  // a well-formed NSID still round-trips and simply reads back as `nil` from
  // `typed`.
  private static func formatStringInit(_ collection: String) -> ExprSyntax {
    ExprSyntax(
      FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("FormatString<NSID>")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
          LabeledExprSyntax(
            label: .identifier("rawValue"),
            colon: .colonToken(),
            expression: StringLiteralExprSyntax(content: collection)
          )
        ]),
        rightParen: .rightParenToken()
      )
    )
  }

  private static func optionalStringExpr(_ value: String?) -> ExprSyntax {
    if let value {
      ExprSyntax(StringLiteralExprSyntax(content: value))
    } else {
      ExprSyntax(NilLiteralExprSyntax())
    }
  }
}
