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
  /// Whether the limit applies to each element of an array field (from its
  /// `items`) rather than to the field's value itself.
  var appliesToElements = false

  /// The constant's name: the field's name followed by the keyword, so that
  /// `text` and `maxGraphemes` give `textMaxGraphemes`. A limit on the
  /// elements has `Item` in between: `tagsItemMaxGraphemes`.
  func constantName(for field: String) -> String {
    field + (appliesToElements ? "Item" : "") + keyword.prefix(1).uppercased() + String(keyword.dropFirst())
  }

  /// The same limit, applied to each element of an array.
  var forElements: Self {
    var constraint = self
    constraint.appliesToElements = true
    return constraint
  }
}

extension LexiconConstraint {
  /// The `Constraints` enum that holds the limits of `properties`, so that a
  /// client can read a limit (a blob's size before uploading it, say) without
  /// copying the number from the Lexicon.
  ///
  /// Returns `nil` when no property declares a limit. `ts` is the schema of
  /// the type that holds `properties`, which resolves their references.
  static func constantsEnumDecl(properties: [(String, FieldTypeDefinition)], ts: TypeSchema, defMap: ExtDefMap) -> EnumDeclSyntax? {
    let decls = properties.flatMap { key, property in property.constraintConstantDecls(for: key, ts: ts, defMap: defMap) }
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
  /// Whether this field declares a limit, here or in a string definition it
  /// refers to. `ts` is the schema that holds the field.
  func hasConstraints(ts: TypeSchema, defMap: ExtDefMap) -> Bool {
    !constraints(ts: ts, defMap: defMap).isEmpty
  }

  /// The limits this field declares that the generated code checks.
  ///
  /// Strings with an `enum` are checked by their closed set of cases instead,
  /// so their length limits are left out. An array's limits are followed by
  /// those of its `items`, which apply to each element. A reference to a
  /// string definition brings that definition's limits.
  ///
  /// `ts` is the schema that holds the field, which resolves its references;
  /// there is no form without it, so that no caller can miss the limits of a
  /// referenced definition.
  func constraints(ts: TypeSchema, defMap: ExtDefMap) -> [LexiconConstraint] {
    constraints(asElement: false, ts: ts, defMap: defMap)
  }

  /// The limits, for a value of this type held as a field (`asElement` false)
  /// or as an element of an array (`asElement` true).
  ///
  /// The two differ only in how a string is wrapped, which decides whether the
  /// guard measures `rawValue`: a field with `knownValues` gets a type of its
  /// own, while an element with `knownValues` stays a `Swift.String`. A `format`
  /// wraps both in `FormatString`.
  private func constraints(asElement: Bool, ts: TypeSchema, defMap: ExtDefMap) -> [LexiconConstraint] {
    switch self {
    case .string(let def) where def.enum == nil:
      let wrapped = (!asElement && def.knownValues != nil) || def.format?.swiftFormatTypeName != nil
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
      ].compactMap { $0 } + def.items.constraints(asElement: true, ts: ts, defMap: defMap).map(\.forElements)
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
    case .ref(let def):
      // A referenced string definition has the type it is generated with
      // wherever it is referenced: its own type with `knownValues`,
      // `FormatString` with a `format`. So it is measured as a field, even as
      // an element of an array. Its own references resolve in its schema.
      // Integer definitions get no type of their own, so only strings are
      // looked through; objects and unions check themselves.
      let target = ts.lookupRef(ref: def.ref, defMap: defMap)
      guard case .string(let string) = target.type, string.enum == nil else { return [] }
      return target.type.constraints(asElement: false, ts: target, defMap: defMap)
    default:
      return []
    }
  }

  /// The names of the constants that
  /// ``constraintConstantDecls(for:ts:defMap:)`` declares for this field, in
  /// the same order.
  func constraintConstantNames(for key: String, ts: TypeSchema, defMap: ExtDefMap) -> [String] {
    constraints(ts: ts, defMap: defMap).map { $0.constantName(for: key) }
  }

  /// The `static let` declarations of this field's limits, for the
  /// `Constraints` enum of the type that holds the field.
  func constraintConstantDecls(for key: String, ts: TypeSchema, defMap: ExtDefMap) -> [VariableDeclSyntax] {
    constraints(ts: ts, defMap: defMap).map { constraint in
      let subject = constraint.appliesToElements ? "each element of `\(key)`" : "`\(key)`"
      return VariableDeclSyntax(
        leadingTrivia: [
          .newlines(1),
          .docLineComment("/// The `\(constraint.keyword)` of \(subject) in the Lexicon."),
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

  func constraintGuardItems(for key: String, optional: Bool, ts: TypeSchema, defMap: ExtDefMap) -> CodeBlockItemListSyntax {
    let ref = key.escapedSwiftKeyword
    let all = constraints(ts: ts, defMap: defMap)
    // The field's own limits first, then one loop over the elements, so an
    // array that is too long is reported before any of its elements.
    var stmts = all.filter { !$0.appliesToElements }.map {
      constraintGuardItem($0, ref: ref, field: key, label: ExprSyntax(StringLiteralExprSyntax(content: key)))
    }
    let elementConstraints = all.filter(\.appliesToElements)
    if !elementConstraints.isEmpty {
      stmts.append(elementLoop(elementConstraints, ref: ref, field: key))
    }
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

  /// `for (index, element) in field.enumerated() { … }` with a guard for each
  /// limit on the elements. The error names the element as `field[index]`.
  private func elementLoop(_ constraints: [LexiconConstraint], ref: String, field: String) -> CodeBlockItemSyntax {
    // `field[\(index)]`, built as a string literal with an interpolation.
    let label = StringLiteralExprSyntax(
      openingQuote: .stringQuoteToken(),
      segments: StringLiteralSegmentListSyntax([
        .stringSegment(StringSegmentSyntax(content: .stringSegment("\(field)["))),
        .expressionSegment(
          ExpressionSegmentSyntax(
            expressions: LabeledExprListSyntax([
              LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("index")))
            ]))),
        .stringSegment(StringSegmentSyntax(content: .stringSegment("]"))),
      ]),
      closingQuote: .stringQuoteToken()
    )
    return CodeBlockItemSyntax(
      item: .stmt(
        StmtSyntax(
          ForStmtSyntax(
            pattern: TuplePatternSyntax(
              elements: TuplePatternElementListSyntax([
                TuplePatternElementSyntax(
                  pattern: IdentifierPatternSyntax(identifier: .identifier("index")), trailingComma: .commaToken()),
                TuplePatternElementSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("element"))),
              ])),
            sequence: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .lexIdentifier(ref)),
                declName: DeclReferenceExprSyntax(baseName: .identifier("enumerated"))
              ))
          ) {
            for constraint in constraints {
              constraintGuardItem(constraint, ref: "element", field: field, label: ExprSyntax(label))
            }
          }
        )))
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

  /// A guard that `ref` keeps `constraint`, throwing the error with `label` as
  /// the field it names. `field` is the Lexicon field, which names the constant.
  private func constraintGuardItem(_ constraint: LexiconConstraint, ref: String, field: String, label: ExprSyntax) -> CodeBlockItemSyntax {
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
                  base: Lex.refExpr(Lex.runtime("LexiconConstraintError")),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier(constraint.errorCase))
                )
              ) {
                LabeledExprSyntax(expression: label)
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
