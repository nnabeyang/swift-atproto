import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension TokenSyntax {
  static func lexIdentifier(_ name: String) -> TokenSyntax {
    .identifier(name.escapedSwiftKeyword)
  }
}

extension String {
  var lexIdentifierSegments: [TokenSyntax] {
    split(separator: ".", omittingEmptySubsequences: false).map { .lexIdentifier(String($0)) }
  }
}

extension Lex {
  static func typeSyntax(_ name: String) -> TypeSyntax {
    if name.hasPrefix("["), name.hasSuffix("]") {
      return TypeSyntax(ArrayTypeSyntax(element: typeSyntax(String(name.dropFirst().dropLast()))))
    }
    let segments = name.lexIdentifierSegments
    if segments.count <= 1 {
      return TypeSyntax(IdentifierTypeSyntax(name: .lexIdentifier(name)))
    }
    return TypeSyntax(MemberTypeSyntax(parts: segments))
  }

  static func refExpr(_ name: String) -> ExprSyntax {
    let segments = name.lexIdentifierSegments
    if segments.count <= 1 {
      return ExprSyntax(DeclReferenceExprSyntax(baseName: .lexIdentifier(name)))
    }
    return ExprSyntax(MemberAccessExprSyntax(parts: segments))
  }
}

extension MemberAccessExprSyntax {
  init(leadingTrivia: Trivia? = nil, parts: [TokenSyntax], isRoot: Bool = true) {
    precondition(!parts.isEmpty, "MemberAccessExprSyntax.init(parts:) requires at least one token.")
    if parts.count == 1 {
      self.init(
        leadingTrivia: leadingTrivia,
        declName: DeclReferenceExprSyntax(baseName: parts[0])
      )
    } else {
      let initialBase = ExprSyntax(DeclReferenceExprSyntax(baseName: parts[0]))
      let finalExpr = parts.dropFirst().dropLast().reduce(initialBase) { currentBase, token in
        ExprSyntax(MemberAccessExprSyntax(base: currentBase, declName: DeclReferenceExprSyntax(baseName: token)))
      }
      self.init(
        leadingTrivia: leadingTrivia,
        base: finalExpr,
        declName: DeclReferenceExprSyntax(baseName: parts.last!)
      )
    }
  }
}

extension MemberTypeSyntax {
  init(leadingTrivia: Trivia? = nil, parts: [TokenSyntax], isRoot: Bool = true) {
    precondition(parts.count >= 2, "MemberAccessExprSyntax.init(parts:) requires at least one token.")
    let initialBase = TypeSyntax(IdentifierTypeSyntax(name: parts[0]))
    let finalExpr = parts.dropFirst().dropLast().reduce(initialBase) { currentBase, token in
      TypeSyntax(MemberTypeSyntax(baseType: currentBase, name: token))
    }
    self.init(
      leadingTrivia: leadingTrivia,
      baseType: finalExpr,
      name: parts.last!
    )
  }
}

extension InheritanceClauseSyntax {
  // Names may be dotted (e.g. `"Swift.String"`) — build a `MemberTypeSyntax`
  // in that case so the raw type / protocol is emitted fully-qualified.
  package init(typeNames: [String]) {
    self.init {
      for name in typeNames {
        InheritedTypeSyntax(type: Lex.typeSyntax(name))
      }
    }
  }
}

extension StringLiteralExprSyntax {
  init(
    leadingTrivia: Trivia? = nil,
    openingQuote: TokenSyntax = .stringQuoteToken(), closingQuote: TokenSyntax = .stringQuoteToken(),
    @StringLiteralSegmentListBuilder itemsBuilder: () throws -> StringLiteralSegmentListSyntax
  ) rethrows {
    self.init(
      openingQuote: openingQuote,
      segments: try itemsBuilder(),
      closingQuote: closingQuote
    )
  }
}

extension ClosureExprSyntax {
  init(
    leadingTrivia: Trivia? = nil,
    leftBrace: TokenSyntax = .leftBraceToken(), rightBrace: TokenSyntax = .rightBraceToken(),
    @ClosureShorthandParameterListBuilder signaturesBuilder: () throws -> ClosureShorthandParameterListSyntax,
    @CodeBlockItemListBuilder statementsBuilder: () throws -> CodeBlockItemListSyntax
  ) rethrows {
    try self.init(
      leftBrace: leftBrace,
      signature: ClosureSignatureSyntax(
        parameterClause: .simpleInput(try signaturesBuilder())),
      rightBrace: rightBrace,
      statementsBuilder: statementsBuilder
    )
  }
}

package func varDecl(ident: String, type: MemberTypeSyntax) -> VariableDeclSyntax {
  VariableDeclSyntax(
    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
    bindingSpecifier: .keyword(.var)
  ) {
    PatternBindingSyntax(
      pattern: IdentifierPatternSyntax(identifier: .identifier(ident)),
      typeAnnotation: TypeAnnotationSyntax(type: type)
    )
  }
}

package func staticLetDecl(leadingTrivia: Trivia? = nil, ident: String, value: some ExprSyntaxProtocol) -> VariableDeclSyntax {
  VariableDeclSyntax(
    leadingTrivia: leadingTrivia,
    modifiers: [
      DeclModifierSyntax(name: .keyword(.public)),
      DeclModifierSyntax(name: .keyword(.static)),
    ],
    bindingSpecifier: .keyword(.let)
  ) {
    PatternBindingSyntax(
      pattern: IdentifierPatternSyntax(identifier: .identifier(ident)),
      initializer: InitializerClauseSyntax(value: value)
    )
  }
}

package func memberInitializer(leadingTrivia: Trivia? = nil, members: [(String, MemberTypeSyntax)]) -> InitializerDeclSyntax {
  InitializerDeclSyntax(
    leadingTrivia: leadingTrivia,
    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
    signature: FunctionSignatureSyntax(
      parameterClause: FunctionParameterClauseSyntax(rightParen: .rightParenToken(leadingTrivia: .newline)) {
        for (firstName, member) in members {
          FunctionParameterSyntax(
            leadingTrivia: .newline,
            firstName: .identifier(firstName),
            colon: .colonToken(),
            type: member
          )
        }
      }
    )
  ) {
    for (firstName, _) in members {
      SequenceExprSyntax {
        MemberAccessExprSyntax(
          leadingTrivia: .newline,
          base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
          period: .periodToken(),
          declName: DeclReferenceExprSyntax(baseName: .identifier(firstName))
        )
        AssignmentExprSyntax(equal: .equalToken())
        DeclReferenceExprSyntax(baseName: .identifier(firstName))
      }
    }
  }
}

extension GenericArgumentSyntax {
  static func create(argument: some TypeSyntaxProtocol) -> GenericArgumentSyntax {
    #if canImport(SwiftSyntax601)
      GenericArgumentSyntax(
        argument: GenericArgumentSyntax.Argument(argument)
      )
    #else
      GenericArgumentSyntax(argument: argument)
    #endif
  }
}

extension MemberBlockItemListSyntax {
  static let empty = Self(itemsBuilder: {})
}

extension CodeBlockItemListSyntax {
  static let empty = Self(itemsBuilder: {})
}

@CodeBlockItemListBuilder
func combine(_ parts: [CodeBlockItemListSyntax]) -> CodeBlockItemListSyntax {
  for part in parts {
    part
  }
}

@MemberBlockItemListBuilder
func combine(_ parts: [MemberBlockItemListSyntax]) -> MemberBlockItemListSyntax {
  for part in parts {
    part
  }
}
