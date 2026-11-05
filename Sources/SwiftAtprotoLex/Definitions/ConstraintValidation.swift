import SwiftSyntax
import SwiftSyntaxBuilder

/// One limit a Lexicon field declares, with everything needed to emit both its
/// constant in `Constraints` and the guard that checks it.
///
/// The constant and the guard are built from the same value so that the
/// number a client reads and the number the generated code enforces cannot
/// drift apart.
struct LexiconConstraint {
  /// What the guard measures on the field's value.
  enum Measure {
    /// `value.utf8.count`, or `value.rawValue.utf8.count` for wrapped strings.
    case utf8Count(wrapped: Bool)
    /// `value.count` on a `String`, which counts grapheme clusters.
    case graphemeCount(wrapped: Bool)
    /// `value.count` on an array or `Data`.
    case count
    /// The integer itself.
    case value
    /// `Swift.Int(value.size)` on a blob.
    case blobSize
  }

  /// The Lexicon keyword, such as `maxLength`. Used in the constant's
  /// documentation.
  let keyword: String
  let value: Int
  let measure: Measure
  /// `<=` for an upper bound, `>=` for a lower bound.
  let op: String
  /// The `LexiconConstraintError` case thrown on a violation.
  let errorCase: String
  /// The label of the error case's limit argument.
  let argLabel: String

  /// The constant's name: the field's name followed by the keyword, so that
  /// `text` and `maxGraphemes` give `textMaxGraphemes`.
  func constantName(for field: String) -> String {
    field + keyword.prefix(1).uppercased() + keyword.dropFirst()
  }
}

extension LexiconConstraint {
  /// The `Constraints` enum that holds the limits of `properties`, so that a
  /// client can read a limit (a blob's size before uploading it, say) without
  /// copying the number from the Lexicon.
  ///
  /// Returns `nil` when no property declares a limit.
  static func constantsEnumDecl(properties: [(String, FieldTypeDefinition)]) -> EnumDeclSyntax? {
    let decls = properties.flatMap { key, property in property.constraintConstantDecls(for: key) }
    guard !decls.isEmpty else { return nil }
    return EnumDeclSyntax(
      leadingTrivia: [
        .newlines(2),
        .docLineComment("/// The limits that the Lexicon declares for the fields of this type."),
        .newlines(1),
      ],
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .identifier(ValidationDecl.constantsEnumName)
    ) {
      for decl in decls { decl }
    }
  }
}

extension FieldTypeDefinition {
  var hasConstraints: Bool {
    !constraints.isEmpty
  }

  /// The limits this field declares that the generated code checks.
  ///
  /// Strings with an `enum` are checked by their closed set of cases instead,
  /// so their length limits are left out.
  var constraints: [LexiconConstraint] {
    switch self {
    case .string(let def) where def.enum == nil:
      let wrapped = def.knownValues != nil || def.format?.swiftFormatTypeName != nil
      return [
        def.maxLength.map {
          LexiconConstraint(keyword: "maxLength", value: $0, measure: .utf8Count(wrapped: wrapped), op: "<=", errorCase: "stringTooLong", argLabel: "limit")
        },
        def.minLength.map {
          LexiconConstraint(keyword: "minLength", value: $0, measure: .utf8Count(wrapped: wrapped), op: ">=", errorCase: "stringTooShort", argLabel: "minimum")
        },
        def.maxGraphemes.map {
          LexiconConstraint(keyword: "maxGraphemes", value: $0, measure: .graphemeCount(wrapped: wrapped), op: "<=", errorCase: "tooManyGraphemes", argLabel: "limit")
        },
        def.minGraphemes.map {
          LexiconConstraint(keyword: "minGraphemes", value: $0, measure: .graphemeCount(wrapped: wrapped), op: ">=", errorCase: "tooFewGraphemes", argLabel: "minimum")
        },
      ].compactMap { $0 }
    case .integer(let def):
      return [
        def.minimum.map {
          LexiconConstraint(keyword: "minimum", value: $0, measure: .value, op: ">=", errorCase: "integerBelowMinimum", argLabel: "minimum")
        },
        def.maximum.map {
          LexiconConstraint(keyword: "maximum", value: $0, measure: .value, op: "<=", errorCase: "integerAboveMaximum", argLabel: "maximum")
        },
      ].compactMap { $0 }
    case .array(let def):
      return [
        def.maxLength.map {
          LexiconConstraint(keyword: "maxLength", value: $0, measure: .count, op: "<=", errorCase: "arrayTooLong", argLabel: "limit")
        },
        def.minLength.map {
          LexiconConstraint(keyword: "minLength", value: $0, measure: .count, op: ">=", errorCase: "arrayTooShort", argLabel: "minimum")
        },
      ].compactMap { $0 }
    case .bytes(let def):
      return [
        def.maxLength.map {
          LexiconConstraint(keyword: "maxLength", value: $0, measure: .count, op: "<=", errorCase: "bytesTooLong", argLabel: "limit")
        },
        def.minLength.map {
          LexiconConstraint(keyword: "minLength", value: $0, measure: .count, op: ">=", errorCase: "bytesTooShort", argLabel: "minimum")
        },
      ].compactMap { $0 }
    case .blob(let def):
      return [
        def.maxSize.map {
          LexiconConstraint(keyword: "maxSize", value: $0, measure: .blobSize, op: "<=", errorCase: "blobTooLarge", argLabel: "limit")
        }
      ].compactMap { $0 }
    default:
      return []
    }
  }

  /// The `static let` declarations of this field's limits, for the
  /// `Constraints` enum of the type that holds the field.
  func constraintConstantDecls(for key: String) -> [VariableDeclSyntax] {
    constraints.map { constraint in
      VariableDeclSyntax(
        leadingTrivia: [
          .newlines(1),
          .docLineComment("/// The `\(constraint.keyword)` of `\(key)` in the Lexicon."),
          .newlines(1),
        ],
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public)),
          DeclModifierSyntax(name: .keyword(.static)),
        ],
        bindingSpecifier: .keyword(.let)
      ) {
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .lexIdentifier(constraint.constantName(for: key))),
          typeAnnotation: TypeAnnotationSyntax(type: Lex.typeSyntax("Swift.Int")),
          initializer: InitializerClauseSyntax(
            value: IntegerLiteralExprSyntax(literal: .integerLiteral("\(constraint.value)"))
          )
        )
      }
    }
  }

  func constraintGuardItems(for key: String, optional: Bool) -> CodeBlockItemListSyntax {
    let ref = key.escapedSwiftKeyword
    let stmts = constraints.map { constraintGuardItem($0, ref: ref, field: key) }
    guard !stmts.isEmpty else { return [] }
    if optional {
      return CodeBlockItemListSyntax([
        CodeBlockItemSyntax(
          item: .expr(
            ExprSyntax(
              IfExprSyntax(
                conditions: ConditionElementListSyntax {
                  OptionalBindingConditionSyntax(
                    bindingSpecifier: .keyword(.let),
                    pattern: IdentifierPatternSyntax(identifier: .lexIdentifier(ref))
                  )
                }
              ) {
                for stmt in stmts { stmt }
              }
            )
          )
        )
      ])
    } else {
      return CodeBlockItemListSyntax(stmts)
    }
  }

  private func measuredExpr(_ measure: LexiconConstraint.Measure, ref: String) -> ExprSyntax {
    switch measure {
    case .utf8Count(let wrapped):
      let base: [TokenSyntax] = wrapped ? [.identifier(ref), .identifier("rawValue")] : [.identifier(ref)]
      return ExprSyntax(MemberAccessExprSyntax(parts: base + [.identifier("utf8"), .identifier("count")]))
    case .graphemeCount(let wrapped):
      let base: [TokenSyntax] = wrapped ? [.identifier(ref), .identifier("rawValue")] : [.identifier(ref)]
      return ExprSyntax(MemberAccessExprSyntax(parts: base + [.identifier("count")]))
    case .count:
      return ExprSyntax(MemberAccessExprSyntax(parts: [.identifier(ref), .identifier("count")]))
    case .value:
      return ExprSyntax(DeclReferenceExprSyntax(baseName: .lexIdentifier(ref)))
    case .blobSize:
      return ExprSyntax(
        FunctionCallExprSyntax(callee: Lex.refExpr("Swift.Int")) {
          LabeledExprSyntax(
            expression: MemberAccessExprSyntax(parts: [.lexIdentifier(ref), .identifier("size")])
          )
        })
    }
  }

  private func constraintGuardItem(_ constraint: LexiconConstraint, ref: String, field: String) -> CodeBlockItemSyntax {
    // Both sides of the check and the limit in the error read the constant,
    // so the value lives in one place.
    let constant = {
      MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .identifier(ValidationDecl.constantsEnumName)),
        declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(constraint.constantName(for: field)))
      )
    }
    return CodeBlockItemSyntax(
      item: .stmt(
        StmtSyntax(
          GuardStmtSyntax(
            conditions: ConditionElementListSyntax {
              SequenceExprSyntax {
                measuredExpr(constraint.measure, ref: ref)
                BinaryOperatorExprSyntax(operator: .binaryOperator(constraint.op))
                constant()
              }
            }
          ) {
            ThrowStmtSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("LexiconConstraintError")),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier(constraint.errorCase))
                )
              ) {
                LabeledExprSyntax(expression: StringLiteralExprSyntax(content: field))
                LabeledExprSyntax(
                  label: .identifier(constraint.argLabel),
                  colon: .colonToken(),
                  expression: constant()
                )
              }
            )
          }
        )
      )
    )
  }
}
