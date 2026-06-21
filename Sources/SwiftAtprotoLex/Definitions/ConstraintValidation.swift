import SwiftSyntax
import SwiftSyntaxBuilder

extension FieldTypeDefinition {
  var hasConstraints: Bool {
    switch self {
    case .string(let def) where def.enum == nil:
      def.maxLength != nil || def.minLength != nil || def.maxGraphemes != nil || def.minGraphemes != nil
    case .integer(let def):
      def.minimum != nil
    default:
      false
    }
  }

  func constraintGuardItems(for key: String, optional: Bool) -> CodeBlockItemListSyntax {
    let ref = key.escapedSwiftKeyword
    let stmts = constraintGuardStmts(ref: ref, field: key)
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

  private func constraintGuardItem(
    lhs: some ExprSyntaxProtocol,
    op: String,
    rhs: Int,
    errorCase: String,
    field: String,
    argLabel: String
  ) -> CodeBlockItemSyntax {
    CodeBlockItemSyntax(
      item: .stmt(
        StmtSyntax(
          GuardStmtSyntax(
            conditions: ConditionElementListSyntax {
              SequenceExprSyntax {
                lhs
                BinaryOperatorExprSyntax(operator: .binaryOperator(op))
                IntegerLiteralExprSyntax(literal: .integerLiteral("\(rhs)"))
              }
            }
          ) {
            ThrowStmtSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("LexiconConstraintError")),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier(errorCase))
                )
              ) {
                LabeledExprSyntax(expression: StringLiteralExprSyntax(content: field))
                LabeledExprSyntax(
                  label: .identifier(argLabel),
                  colon: .colonToken(),
                  expression: IntegerLiteralExprSyntax(literal: .integerLiteral("\(rhs)"))
                )
              }
            )
          }
        )
      )
    )
  }

  private func constraintGuardStmts(ref: String, field: String) -> [CodeBlockItemSyntax] {
    switch self {
    case .string(let def) where def.enum == nil && def.knownValues == nil:
      var items = [CodeBlockItemSyntax]()
      if let n = def.maxLength {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(parts: [.identifier(ref), .identifier("utf8"), .identifier("count")]),
            op: "<=",
            rhs: n,
            errorCase: "stringTooLong",
            field: field,
            argLabel: "limit"
          ))
      }
      if let n = def.minLength {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(parts: [.identifier(ref), .identifier("utf8"), .identifier("count")]),
            op: ">=",
            rhs: n,
            errorCase: "stringTooShort",
            field: field,
            argLabel: "minimum"
          ))
      }
      if let n = def.maxGraphemes {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(parts: [.identifier(ref), .identifier("count")]),
            op: "<=",
            rhs: n,
            errorCase: "tooManyGraphemes",
            field: field,
            argLabel: "limit"
          ))
      }
      if let n = def.minGraphemes {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(parts: [.identifier(ref), .identifier("count")]),
            op: ">=",
            rhs: n,
            errorCase: "tooFewGraphemes",
            field: field,
            argLabel: "minimum"
          ))
      }
      return items
    case .string(let def) where def.enum == nil && def.knownValues != nil:
      var items = [CodeBlockItemSyntax]()
      if let n = def.maxLength {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(
              parts: [.identifier(ref), .identifier("rawValue"), .identifier("utf8"), .identifier("count")]),
            op: "<=",
            rhs: n,
            errorCase: "stringTooLong",
            field: field,
            argLabel: "limit"
          ))
      }
      if let n = def.minLength {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(
              parts: [.identifier(ref), .identifier("rawValue"), .identifier("utf8"), .identifier("count")]),
            op: ">=",
            rhs: n,
            errorCase: "stringTooShort",
            field: field,
            argLabel: "minimum"
          ))
      }
      if let n = def.maxGraphemes {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(
              parts: [.identifier(ref), .identifier("rawValue"), .identifier("count")]),
            op: "<=",
            rhs: n,
            errorCase: "tooManyGraphemes",
            field: field,
            argLabel: "limit"
          ))
      }
      if let n = def.minGraphemes {
        items.append(
          constraintGuardItem(
            lhs: MemberAccessExprSyntax(
              parts: [.identifier(ref), .identifier("rawValue"), .identifier("count")]),
            op: ">=",
            rhs: n,
            errorCase: "tooFewGraphemes",
            field: field,
            argLabel: "minimum"
          ))
      }
      return items
    case .integer(let def):
      var items = [CodeBlockItemSyntax]()
      if let n = def.minimum {
        items.append(
          constraintGuardItem(
            lhs: DeclReferenceExprSyntax(baseName: .lexIdentifier(ref)),
            op: ">=",
            rhs: n,
            errorCase: "integerBelowMinimum",
            field: field,
            argLabel: "minimum"
          ))
      }
      return items
    default:
      return []
    }
  }
}
