import Foundation
import SwiftSyntax

protocol HTTPAPITypeDefinition: Encodable, DecodableWithConfiguration, SwiftCodeGeneratable {
  associatedtype DecodingConfiguration = TypeSchema.DecodingConfiguration
  var type: FieldType { get }
  var output: OutputType? { get }
  var description: String? { get }
  var errors: [ErrorResponse]? { get }
  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String, protocolRequirement: Bool) -> [FunctionParameterSyntax]
  func rpcOutput(fname: String, defMap: ExtDefMap, prefix: String) -> ReturnClauseSyntax
  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol
  func makeErrorDeclaration(leadingTrivia: Trivia?, ts: TypeSchema, name typeName: String, type: String) -> any DeclSyntaxProtocol
}

extension HTTPAPITypeDefinition {
  func rpcOutput(fname: String, defMap: ExtDefMap, prefix: String) -> ReturnClauseSyntax {
    ReturnClauseSyntax(type: IdentifierTypeSyntax(name: output?.typeName(fname: fname, prefix: prefix, defMap: defMap, isOutput: true) ?? .identifier("Bool")))
  }

  func makeErrorDeclaration(leadingTrivia: Trivia?, ts: TypeSchema, name typeName: String, type: String) -> any DeclSyntaxProtocol {
    let errors = self.errors ?? []
    return EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.indirect)),
      ],
      name: .init(stringLiteral: "Error"),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["XRPCError"])
    ) {
      for error in errors.sorted() {
        EnumCaseDeclSyntax {
          EnumCaseElementSyntax(
            name: .identifier(error.name.camelCased()),
            parameterClause: EnumCaseParameterClauseSyntax(
              parameters: [
                EnumCaseParameterSyntax(type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String"))))
              ]
            )
          )
        }
      }
      EnumCaseDeclSyntax {
        EnumCaseElementSyntax(
          name: .identifier("unexpected"),
          parameterClause: EnumCaseParameterClauseSyntax(
            parameters: [
              EnumCaseParameterSyntax(
                firstName: .identifier("error"),
                colon: .colonToken(),
                type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String"))),
                trailingComma: .commaToken()
              ),
              EnumCaseParameterSyntax(
                firstName: .identifier("message"),
                colon: .colonToken(),
                type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String")))
              ),
            ]
          )
        )
      }

      InitializerDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        signature: FunctionSignatureSyntax(
          parameterClause: FunctionParameterClauseSyntax {
            FunctionParameterSyntax(firstName: .identifier("error"), type: TypeSyntax(stringLiteral: "UnExpectedError"))
          }
        )
      ) {
        SwitchExprSyntax(subject: ExprSyntax(stringLiteral: "error.error")) {
          for error in errors {
            SwitchCaseSyntax(
              label: SwitchCaseSyntax.Label(
                SwitchCaseLabelSyntax(
                  caseItems: [
                    SwitchCaseItemSyntax(
                      pattern: ExpressionPatternSyntax(expression: StringLiteralExprSyntax(content: error.name)))
                  ],
                  colon: .colonToken()
                ))
            ) {
              SequenceExprSyntax {
                DeclReferenceExprSyntax(baseName: .keyword(.self))
                AssignmentExprSyntax(equal: .equalToken())
                FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(error.name.camelCased()))
                  )
                ) {
                  LabeledExprSyntax(
                    expression: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("message"))
                      )))
                }
              }
            }
          }

          SwitchCaseSyntax(
            label: SwitchCaseSyntax.Label(
              SwitchDefaultLabelSyntax(
                colon: .colonToken()
              )),
            statements: CodeBlockItemListSyntax([
              CodeBlockItemSyntax(
                item: CodeBlockItemSyntax.Item(
                  SequenceExprSyntax {
                    DeclReferenceExprSyntax(baseName: .keyword(.self))
                    AssignmentExprSyntax(equal: .equalToken())
                    FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("unexpected"))
                      )
                    ) {
                      LabeledExprSyntax(
                        label: .identifier("error"),
                        colon: .colonToken(),
                        expression: MemberAccessExprSyntax(
                          base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error"))),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("error"))
                        ),
                        trailingComma: .commaToken()
                      )
                      LabeledExprSyntax(
                        label: .identifier("message"),
                        colon: .colonToken(),
                        expression: MemberAccessExprSyntax(
                          base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error"))),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("message"))
                        )
                      )
                    }
                  }
                ))
            ])
          )
        }
      }

      VariableDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: DeclModifierListSyntax([
          DeclModifierSyntax(name: .keyword(.public))
        ]),
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("error")),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String")))
            ),
            accessorBlock: AccessorBlockSyntax(
              accessors: .getter(
                CodeBlockItemListSyntax {
                  SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
                    for error in errors {
                      SwitchCaseSyntax(
                        label: SwitchCaseSyntax.Label(
                          SwitchCaseLabelSyntax(
                            caseItems: [
                              SwitchCaseItemSyntax(
                                pattern: ExpressionPatternSyntax(
                                  expression: MemberAccessExprSyntax(
                                    period: .periodToken(),
                                    declName: DeclReferenceExprSyntax(baseName: .identifier(error.name.camelCased()))
                                  )
                                )
                              )
                            ],
                            colon: .colonToken()
                          ))
                      ) {
                        ReturnStmtSyntax(expression: StringLiteralExprSyntax(content: error.name))
                      }
                    }
                    SwitchCaseSyntax(
                      label: SwitchCaseSyntax.Label(
                        SwitchCaseLabelSyntax(
                          caseItems: [
                            SwitchCaseItemSyntax(
                              pattern: ValueBindingPatternSyntax(
                                bindingSpecifier: .keyword(.let),
                                pattern: ExpressionPatternSyntax(
                                  expression: FunctionCallExprSyntax(
                                    callee: MemberAccessExprSyntax(
                                      period: .periodToken(),
                                      declName: DeclReferenceExprSyntax(baseName: .identifier("unexpected"))
                                    )
                                  ) {
                                    LabeledExprSyntax(
                                      expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("error"))),
                                      trailingComma: .commaToken()
                                    )
                                    LabeledExprSyntax(expression: DiscardAssignmentExprSyntax(wildcard: .wildcardToken()))
                                  }
                                )
                              ))
                          ],
                          colon: .colonToken()
                        ))
                    ) {
                      ReturnStmtSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("error")))
                    }
                  }
                }
              )
            )
          )
        ])
      )

      VariableDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: DeclModifierListSyntax([
          DeclModifierSyntax(name: .keyword(.public))
        ]),
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("message")),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String")))
            ),
            accessorBlock: AccessorBlockSyntax(
              leftBrace: .leftBraceToken(),
              accessors: AccessorBlockSyntax.Accessors(
                CodeBlockItemListSyntax([
                  CodeBlockItemSyntax(
                    item: CodeBlockItemSyntax.Item(
                      SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
                        for error in errors {
                          SwitchCaseSyntax(
                            label: SwitchCaseSyntax.Label(
                              SwitchCaseLabelSyntax(
                                caseItems: SwitchCaseItemListSyntax([
                                  SwitchCaseItemSyntax(
                                    pattern: ValueBindingPatternSyntax(
                                      bindingSpecifier: .keyword(.let),
                                      pattern: ExpressionPatternSyntax(
                                        expression: FunctionCallExprSyntax(
                                          callee: MemberAccessExprSyntax(
                                            period: .periodToken(),
                                            declName: DeclReferenceExprSyntax(baseName: .identifier(error.name.camelCased()))
                                          )
                                        ) {
                                          LabeledExprSyntax(expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("message"))))
                                        }
                                      )
                                    ))
                                ]),
                                colon: .colonToken()
                              )),
                            statements: CodeBlockItemListSyntax {
                              ReturnStmtSyntax(
                                expression: DeclReferenceExprSyntax(baseName: .identifier("message"))
                              )
                            }
                          )
                        }
                        SwitchCaseSyntax(
                          label: SwitchCaseSyntax.Label(
                            SwitchCaseLabelSyntax {
                              SwitchCaseItemSyntax(
                                pattern: ValueBindingPatternSyntax(
                                  bindingSpecifier: .keyword(.let),
                                  pattern: ExpressionPatternSyntax(
                                    expression: ExprSyntax(
                                      FunctionCallExprSyntax(
                                        callee: MemberAccessExprSyntax(
                                          period: .periodToken(),
                                          declName: DeclReferenceExprSyntax(baseName: .identifier("unexpected"))
                                        )
                                      ) {
                                        LabeledExprSyntax(
                                          expression: DiscardAssignmentExprSyntax(wildcard: .wildcardToken()),
                                          trailingComma: .commaToken())
                                        LabeledExprSyntax(
                                          expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("message")))
                                        )
                                      }))
                                ))
                            }
                          ),
                          statements: CodeBlockItemListSyntax {
                            ReturnStmtSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("message")))
                          }
                        )
                      }
                    ))
                ])),
              rightBrace: .rightBraceToken()
            )
          )
        ])
      )
    }
  }
}
