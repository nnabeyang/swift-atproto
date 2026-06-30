import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct PermissionSetTypeDefinition: Codable {
  let type: FieldType
  let title: String?
  let titleLang: [String: String]?
  let detail: String?
  let detailLang: [String: String]?
  let permissions: [PermissionTypeDefinition]

  private enum CodingKeys: String, CodingKey {
    case type
    case title
    case titleLang = "title:lang"
    case detail
    case detailLang = "detail:lang"
    case permissions
  }
}

extension PermissionSetTypeDefinition: SwiftCodeGeneratable {
  func generateDeclaration(
    leadingTrivia: Trivia? = nil, ts _: TypeSchema, name: String, type typeName: String,
    defMap _: ExtDefMap, generate _: GenerateOption
  ) -> any DeclSyntaxProtocol {
    EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .lexIdentifier(name),
      inheritanceClause: InheritanceClauseSyntax {
        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("LexPermissionSet")))
      }
    ) {
      staticLetDecl(leadingTrivia: .newline, ident: "id", value: StringLiteralExprSyntax(content: typeName))
      Self.optionalStringStaticLet(ident: "title", value: title)
      Self.optionalStringStaticLet(ident: "detail", value: detail)
      Self.permissionsStaticLet(permissions: permissions)
    }
  }

  private static func optionalStringStaticLet(ident: String, value: String?) -> VariableDeclSyntax {
    let valueExpr: ExprSyntax =
      if let value {
        ExprSyntax(StringLiteralExprSyntax(content: value))
      } else {
        ExprSyntax(NilLiteralExprSyntax())
      }
    return VariableDeclSyntax(
      leadingTrivia: .newline,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.static)),
      ],
      bindingSpecifier: .keyword(.let)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier(ident)),
        typeAnnotation: TypeAnnotationSyntax(
          type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String")))
        ),
        initializer: InitializerClauseSyntax(value: valueExpr)
      )
    }
  }

  private static func permissionsStaticLet(permissions: [PermissionTypeDefinition]) -> VariableDeclSyntax {
    let arrayExpr = ArrayExprSyntax(
      leftSquare: .leftSquareToken(),
      elements: ArrayElementListSyntax {
        for (i, permission) in permissions.enumerated() {
          ArrayElementSyntax(
            leadingTrivia: .newline,
            expression: permissionInit(permission),
            trailingComma: i < permissions.count - 1 ? .commaToken() : nil
          )
        }
      },
      rightSquare: .rightSquareToken(leadingTrivia: .newline)
    )
    return VariableDeclSyntax(
      leadingTrivia: .newline,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.static)),
      ],
      bindingSpecifier: .keyword(.let)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier("permissions")),
        typeAnnotation: TypeAnnotationSyntax(
          type: ArrayTypeSyntax(element: IdentifierTypeSyntax(name: .identifier("LexPermission")))
        ),
        initializer: InitializerClauseSyntax(value: arrayExpr)
      )
    }
  }

  private static func permissionInit(_ permission: PermissionTypeDefinition) -> ExprSyntax {
    var args: [LabeledExprSyntax] = []
    args.append(labeledArg(label: "resource", expression: resourceExpr(permission.resource)))
    if let aud = permission.aud {
      args.append(labeledArg(label: "aud", expression: StringLiteralExprSyntax(content: aud)))
    }
    if let inheritAud = permission.inheritAud {
      args.append(labeledArg(label: "inheritAud", expression: BooleanLiteralExprSyntax(booleanLiteral: inheritAud)))
    }
    if let lxm = permission.lxm {
      args.append(labeledArg(label: "lxm", expression: stringArrayExpr(lxm)))
    }
    if let action = permission.action {
      args.append(labeledArg(label: "action", expression: actionArrayExpr(action)))
    }
    if let collection = permission.collection {
      args.append(labeledArg(label: "collection", expression: stringArrayExpr(collection)))
    }
    for i in 0..<args.count {
      args[i].leadingTrivia = .newline
      if i < args.count - 1 {
        args[i].trailingComma = .commaToken()
      }
    }
    return ExprSyntax(
      FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("LexPermission")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(args),
        rightParen: .rightParenToken(leadingTrivia: .newline)
      )
    )
  }

  private static func labeledArg(label: String, expression: some ExprSyntaxProtocol) -> LabeledExprSyntax {
    LabeledExprSyntax(
      label: .identifier(label),
      colon: .colonToken(),
      expression: expression
    )
  }

  private static func stringArrayExpr(_ values: [String]) -> ExprSyntax {
    ExprSyntax(
      ArrayExprSyntax(
        leftSquare: .leftSquareToken(),
        elements: ArrayElementListSyntax {
          for (i, value) in values.enumerated() {
            ArrayElementSyntax(
              expression: StringLiteralExprSyntax(content: value),
              trailingComma: i < values.count - 1 ? .commaToken() : nil
            )
          }
        },
        rightSquare: .rightSquareToken()
      )
    )
  }

  private static func actionArrayExpr(_ values: [PermissionAction]) -> ExprSyntax {
    ExprSyntax(
      ArrayExprSyntax(
        leftSquare: .leftSquareToken(),
        elements: ArrayElementListSyntax {
          for (i, value) in values.enumerated() {
            ArrayElementSyntax(
              expression: actionExpr(value),
              trailingComma: i < values.count - 1 ? .commaToken() : nil
            )
          }
        },
        rightSquare: .rightSquareToken()
      )
    )
  }

  private static func resourceExpr(_ resource: PermissionResource) -> ExprSyntax {
    switch resource {
    case .rpc:
      ExprSyntax(MemberAccessExprSyntax(name: .identifier("rpc")))
    case .repo:
      ExprSyntax(MemberAccessExprSyntax(name: .identifier("repo")))
    default:
      ExprSyntax(
        FunctionCallExprSyntax(
          calledExpression: DeclReferenceExprSyntax(baseName: .identifier("LexPermissionResource")),
          leftParen: .leftParenToken(),
          arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
              label: .identifier("rawValue"),
              colon: .colonToken(),
              expression: StringLiteralExprSyntax(content: resource.rawValue)
            )
          ]),
          rightParen: .rightParenToken()
        )
      )
    }
  }

  private static func actionExpr(_ action: PermissionAction) -> ExprSyntax {
    switch action {
    case .create:
      ExprSyntax(MemberAccessExprSyntax(name: .identifier("create")))
    case .update:
      ExprSyntax(MemberAccessExprSyntax(name: .identifier("update")))
    case .delete:
      ExprSyntax(MemberAccessExprSyntax(name: .identifier("delete")))
    default:
      ExprSyntax(
        FunctionCallExprSyntax(
          calledExpression: DeclReferenceExprSyntax(baseName: .identifier("LexPermissionAction")),
          leftParen: .leftParenToken(),
          arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
              label: .identifier("rawValue"),
              colon: .colonToken(),
              expression: StringLiteralExprSyntax(content: action.rawValue)
            )
          ]),
          rightParen: .rightParenToken()
        )
      )
    }
  }
}
