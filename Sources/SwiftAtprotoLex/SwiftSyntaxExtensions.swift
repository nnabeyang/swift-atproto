import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension EnumDeclSyntax {
  public init(
    leadingTrivia: Trivia? = nil,
    modifiers: DeclModifierListSyntax = [],
    parts: [TokenSyntax],
    @MemberBlockItemListBuilder memberBlockBuilder: () throws -> MemberBlockItemListSyntax
  ) rethrows {
    precondition(!parts.isEmpty, "MemberAccessExprSyntax.init(parts:) requires at least one token.")
    if parts.count == 1 {
      try self.init(
        leadingTrivia: leadingTrivia,
        modifiers: modifiers,
        name: parts[0],
        memberBlockBuilder: memberBlockBuilder
      )
    } else {
      let reversed = Array(parts.reversed())
      let initialEnum = try EnumDeclSyntax(modifiers: modifiers, name: reversed[0], memberBlockBuilder: memberBlockBuilder)
      self = reversed.dropFirst().reduce(initialEnum) { currentBase, token in
        EnumDeclSyntax(modifiers: modifiers, name: token) {
          currentBase
        }
      }
    }
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
  package init(typeNames: [String]) {
    self.init {
      for name in typeNames {
        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier(name)))
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
      parameterClause: FunctionParameterClauseSyntax(rightParen: .rightParenToken(leadingTrivia: [.newlines(1), .spaces(4)])) {
        for (firstName, member) in members {
          FunctionParameterSyntax(
            leadingTrivia: [.newlines(1), .spaces(6)],
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
          leadingTrivia: [.newlines(1), .spaces(6)],
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
