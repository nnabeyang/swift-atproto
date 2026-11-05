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

  /// The statements that call `validateConstraints()` on the values nested in
  /// this field, or none when the field holds nothing to validate.
  func nestedValidationItems(for key: String, optional: Bool, ts: TypeSchema, defMap: ExtDefMap) -> [CodeBlockItemSyntax] {
    if isValidatable(ts: ts, defMap: defMap) {
      return [
        CodeBlockItemSyntax(
          item: .expr(Self.validateCall(on: DeclReferenceExprSyntax(baseName: .lexIdentifier(key)), optional: optional)))
      ]
    }
    guard case .array(let def) = self, def.items.isValidatable(ts: ts, defMap: defMap) else {
      return []
    }
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
  static let protocolName = "LexiconValidatable"

  /// The name of the method that checks a value before it is sent.
  static let methodName = "validateConstraints"

  /// The name of the enum that holds a type's limits.
  static let constantsEnumName = "Constraints"

  /// Stops generation when a field would share its name with a declaration
  /// generated next to it, which Swift rejects as a redeclaration.
  ///
  /// The Swift compiler would report this only in the generated file, where
  /// the Lexicon that caused it is no longer visible, so it is reported here
  /// with the schema's NSID instead.
  static func checkNoCollision(fieldNames: [String], ts: TypeSchema, emitsConstants: Bool, emitsValidate: Bool) {
    if emitsValidate, fieldNames.contains(methodName) {
      fatalError("field \(methodName) in \(ts.id) collides with the generated \(methodName)() method")
    }
    if emitsConstants, fieldNames.contains(constantsEnumName) {
      fatalError("field \(constantsEnumName) in \(ts.id) collides with the generated \(constantsEnumName) enum")
    }
  }

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
            type: IdentifierTypeSyntax(name: .identifier("LexiconConstraintError")),
            rightParen: .rightParenToken()
          )
        )
      ),
      body: CodeBlockSyntax(statements: body())
    )
  }
}
