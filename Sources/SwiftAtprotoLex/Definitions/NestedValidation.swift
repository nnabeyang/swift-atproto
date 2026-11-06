import SwiftSyntax
import SwiftSyntaxBuilder

extension FieldTypeDefinition {
  /// Whether a value of this type is a generated type whose
  /// `validateConstraints()` may find violations: an object, a record, a
  /// union, or an `unknown` value.
  ///
  /// Strict decoding reaches the same values because each of them decodes
  /// through its own `init(from:)`, so `validateConstraints()` has to visit
  /// exactly these to report what strict decoding would. `ts` is the schema
  /// that holds the field, which resolves local (`#name`) references.
  func isValidatable(ts: TypeSchema, defMap: ExtDefMap) -> Bool {
    switch self {
    case .object, .union, .unknown:
      true
    case .ref(let def):
      ts.lookupRef(ref: def.ref, defMap: defMap).type.isValidatableDefinition
    default:
      false
    }
  }

  /// Whether a definition generates a type that conforms to
  /// `LexiconValidatable`: an object, a record, or a union.
  var isValidatableDefinition: Bool {
    switch self {
    case .object, .record, .union: true
    default: false
    }
  }

  /// Whether a value of this field, or an element of it when it is an array,
  /// is a generated type whose `validateConstraints()` may find violations.
  ///
  /// This is exactly when ``nestedValidationItems(for:optional:ts:defMap:)``
  /// returns statements, so that the generator and the check for name
  /// collisions agree on which types get a `validateConstraints()`.
  func holdsValidatableValues(ts: TypeSchema, defMap: ExtDefMap) -> Bool {
    if isValidatable(ts: ts, defMap: defMap) { return true }
    guard case .array(let def) = self else { return false }
    return def.items.isValidatable(ts: ts, defMap: defMap)
  }

  /// The statements that call `validateConstraints()` on the values nested in
  /// this field, or none when the field holds nothing to validate.
  func nestedValidationItems(for key: String, optional: Bool, ts: TypeSchema, defMap: ExtDefMap) -> [CodeBlockItemSyntax] {
    guard holdsValidatableValues(ts: ts, defMap: defMap) else { return [] }
    if isValidatable(ts: ts, defMap: defMap) {
      return [
        CodeBlockItemSyntax(
          item: .expr(Self.validateCall(on: DeclReferenceExprSyntax(baseName: .lexIdentifier(key)), optional: optional)))
      ]
    }
    // `holdsValidatableValues` holds, so this is an array of validatable values.
    let field = ExprSyntax(DeclReferenceExprSyntax(baseName: .lexIdentifier(key)))
    // An absent array has no elements to check.
    let sequence: ExprSyntax =
      optional
      ? ExprSyntax(
        SequenceExprSyntax {
          field
          BinaryOperatorExprSyntax(operator: .binaryOperator("??"))
          ArrayExprSyntax(elements: [])
        })
      : field
    return [
      CodeBlockItemSyntax(
        item: .stmt(
          StmtSyntax(
            ForStmtSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("element")),
              sequence: sequence
            ) {
              Self.validateCall(on: DeclReferenceExprSyntax(baseName: .identifier("element")), optional: false)
            }
          )))
    ]
  }

  /// `try value.validateConstraints()`, or
  /// `try value?.validateConstraints()` for an optional.
  static func validateCall(on value: some ExprSyntaxProtocol, optional: Bool) -> ExprSyntax {
    let base: ExprSyntax = optional ? ExprSyntax(OptionalChainingExprSyntax(expression: value)) : ExprSyntax(value)
    return ExprSyntax(
      TryExprSyntax(
        expression: FunctionCallExprSyntax(
          callee: MemberAccessExprSyntax(
            base: base,
            declName: DeclReferenceExprSyntax(baseName: .identifier(ValidationDecl.methodName))
          )
        )
      ))
  }
}

enum ValidationDecl {
  /// The protocol that generated types conform to so that a containing type
  /// can call `validateConstraints()` on them.
  static let protocolName = Lex.runtime("LexiconValidatable")

  /// The name of the method that checks a value before it is sent.
  static let methodName = "validateConstraints"

  /// The name of the enum that holds a type's limits.
  static let constantsEnumName = "Constraints"

  /// `public func validateConstraints() throws(LexiconConstraintError)` with
  /// `body`.
  static func validateDecl(@CodeBlockItemListBuilder body: () -> CodeBlockItemListSyntax) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      leadingTrivia: [
        .newlines(2),
        .docLineComment("/// Checks this value, and the values nested in it, against the limits"),
        .newlines(1),
        .docLineComment("/// that the Lexicon declares."),
        .newlines(1),
        .docLineComment("///"),
        .newlines(1),
        .docLineComment("/// Reports the same violations as decoding the value in"),
        .newlines(1),
        .docLineComment("/// `LexiconDecodingMode.strict`. Call it before sending a value."),
        .newlines(1),
      ],
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .identifier(methodName),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: []),
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          throwsClause: ThrowsClauseSyntax(
            throwsSpecifier: .keyword(.throws),
            leftParen: .leftParenToken(),
            type: Lex.typeSyntax(Lex.runtime("LexiconConstraintError")),
            rightParen: .rightParenToken()
          )
        )
      ),
      body: CodeBlockSyntax(statements: body())
    )
  }
}
