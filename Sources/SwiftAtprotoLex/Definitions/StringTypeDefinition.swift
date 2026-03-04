import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct StringTypeDefinition: Codable, SwiftCodeGeneratable {
  var type: FieldType { .string }
  let description: String?
  let format: StringFormat?
  let maxLength: Int?
  let minLength: Int?
  let maxGraphemes: Int?
  let minGraphemes: Int?
  let knownValues: [String]?
  let `enum`: [String]?
  let const: String?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case format
    case maxLength
    case minLength
    case maxGraphemes
    case minGraphemes
    case knownValues
    case `enum`
    case const
  }

  var isPrimitive: Bool {
    `enum` == nil
  }

  func generateDeclaration(leadingTrivia: Trivia? = nil, ts _: TypeSchema, name: String, type typeName: String, defMap: ExtDefMap, generate: GenerateOption) -> any DeclSyntaxProtocol {
    if let knownValues = knownValues {
      genCodeStringWithKnownValues(leadingTrivia: leadingTrivia, name: name, knownValues: knownValues)
    } else if let cases = `enum` {
      genCodeStringWithEnum(leadingTrivia: leadingTrivia, name: name, cases: cases)
    } else {
      fatalError()
    }
  }

  private func genCodeStringWithEnum(leadingTrivia _: Trivia? = nil, name: String, cases: [String]) -> DeclSyntaxProtocol {
    return DeclSyntax(
      EnumDeclSyntax(
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public)),
          DeclModifierSyntax(name: .keyword(.indirect)),
        ],
        name: .identifier(name),
        inheritanceClause: InheritanceClauseSyntax(typeNames: ["String", "Codable", "Hashable"])
      ) {
        for value in cases {
          EnumCaseDeclSyntax {
            EnumCaseElementSyntax(
              name: .identifier(value.camelCased().escapedSwiftKeyword),
              rawValue: InitializerClauseSyntax(
                equal: .equalToken(),
                value: StringLiteralExprSyntax(
                  openingQuote: .stringQuoteToken(),
                  segments: StringLiteralSegmentListSyntax([
                    StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(value)))
                  ]),
                  closingQuote: .stringQuoteToken()
                )
              )
            )
          }
        }
        decodableInitializerDeclSyntax(leadingTrivia: .newlines(2)) {
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.let),
            bindings: PatternBindingListSyntax([
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: TryExprSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("singleValueContainer"))
                      )
                    )
                  )
                )
              )
            ])
          )
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.let),
            bindings: PatternBindingListSyntax([
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("rawValue")),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: TryExprSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("decode"))
                      )
                    ) {
                      LabeledExprSyntax(
                        expression: MemberAccessExprSyntax(
                          base: DeclReferenceExprSyntax(baseName: .identifier("String")),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                        ))
                    }
                  )
                )
              )
            ])
          )
          GuardStmtSyntax(
            conditions: ConditionElementListSyntax {
              OptionalBindingConditionSyntax(
                bindingSpecifier: .keyword(.let),
                pattern: IdentifierPatternSyntax(identifier: .identifier("value")),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: FunctionCallExprSyntax(
                    callee: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.Self)))
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("rawValue"),
                      colon: .colonToken(),
                      expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                    )
                  }
                )
              )
            }
          ) {
            ThrowStmtSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("DecodingError")),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier("dataCorrupted"))
                )
              ) {
                LabeledExprSyntax(
                  expression:
                    FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
                      )
                    ) {
                      LabeledExprSyntax(
                        label: .identifier("codingPath"),
                        colon: .colonToken(),
                        expression: MemberAccessExprSyntax(
                          base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("codingPath"))
                        ),
                        trailingComma: .commaToken()
                      )
                      LabeledExprSyntax(
                        label: .identifier("debugDescription"),
                        colon: .colonToken(),
                        expression: StringLiteralExprSyntax(
                          openingQuote: .stringQuoteToken(),
                          segments: StringLiteralSegmentListSyntax([
                            StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("invalid rawValue: "))),
                            StringLiteralSegmentListSyntax.Element(
                              ExpressionSegmentSyntax(
                                backslash: .backslashToken(),
                                leftParen: .leftParenToken(),
                                expressions: LabeledExprListSyntax([
                                  LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                                ]),
                                rightParen: .rightParenToken()
                              )),
                            StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(""))),
                          ]),
                          closingQuote: .stringQuoteToken()
                        )
                      )
                    }
                )
              }
            )
          }
          SequenceExprSyntax {
            DeclReferenceExprSyntax(baseName: .keyword(.self))
            AssignmentExprSyntax(equal: .equalToken())
            DeclReferenceExprSyntax(baseName: .identifier("value"))
          }
        }
        encodableFunctionDeclSyntax {
          TryExprSyntax(
            expression: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("rawValue")),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
              )
            ) {
              LabeledExprSyntax(
                label: .identifier("to"),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("encoder"))
              )
            }
          )
        }
      })
  }

  private func genCodeStringWithKnownValues(leadingTrivia: Trivia? = nil, name: String, knownValues: [String]) -> DeclSyntaxProtocol {
    return EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.indirect)),
      ],
      name: .identifier(name),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["RawRepresentable", "Codable", "Hashable", "Sendable"])
    ) {
      for value in knownValues {
        EnumCaseDeclSyntax {
          .init(name: .identifier(value.camelCased()))
        }
      }
      EnumCaseDeclSyntax {
        EnumCaseElementSyntax(
          name: .identifier("_other"),
          parameterClause: EnumCaseParameterClauseSyntax(
            parameters: [
              EnumCaseParameterSyntax(
                type: IdentifierTypeSyntax(name: .identifier("String"))
              )
            ]
          )
        )
      }
      InitializerDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: [.init(name: .keyword(.public))],
        signature: FunctionSignatureSyntax(
          parameterClause: FunctionParameterClauseSyntax {
            FunctionParameterSyntax(firstName: .identifier("rawValue"), type: IdentifierTypeSyntax(name: .identifier("String")))
          }
        )
      ) {
        ExpressionStmtSyntax(
          expression: SwitchExprSyntax(
            subject: DeclReferenceExprSyntax(baseName: .identifier("rawValue"))
          ) {
            for value in knownValues {
              SwitchCaseSyntax(
                label: SwitchCaseSyntax.Label(
                  SwitchCaseLabelSyntax(
                    caseItems: SwitchCaseItemListSyntax([
                      SwitchCaseItemSyntax(
                        pattern: ExpressionPatternSyntax(
                          expression: StringLiteralExprSyntax(
                            openingQuote: .stringQuoteToken(),
                            segments: StringLiteralSegmentListSyntax([
                              StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(value)))
                            ]),
                            closingQuote: .stringQuoteToken()
                          )))
                    ]),
                    colon: .colonToken()
                  ))
              ) {
                SequenceExprSyntax {
                  DeclReferenceExprSyntax(baseName: .keyword(.self))
                  AssignmentExprSyntax(equal: .equalToken())
                  MemberAccessExprSyntax(
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(value.camelCased().escapedSwiftKeyword))
                  )
                }
              }
            }
            SwitchCaseSyntax(
              label: SwitchCaseSyntax.Label(
                SwitchDefaultLabelSyntax(
                  colon: .colonToken()
                ))
            ) {
              SequenceExprSyntax {
                DeclReferenceExprSyntax(baseName: .keyword(.self))
                AssignmentExprSyntax(equal: .equalToken())
                FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("_other"))
                  )
                ) {
                  LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                }
              }
            }
          })
      }
      VariableDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: DeclModifierListSyntax([
          DeclModifierSyntax(name: .keyword(.public))
        ]),
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("rawValue"))),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
            ),
            accessorBlock: AccessorBlockSyntax(
              accessors: AccessorBlockSyntax.Accessors(
                CodeBlockItemListSyntax([
                  CodeBlockItemSyntax(
                    item: CodeBlockItemSyntax.Item(
                      ExpressionStmtSyntax(
                        expression: SwitchExprSyntax(
                          subject: DeclReferenceExprSyntax(baseName: .keyword(.self))
                        ) {
                          for value in knownValues {
                            SwitchCaseSyntax(
                              label: SwitchCaseSyntax.Label(
                                SwitchCaseLabelSyntax(
                                  caseItems: [
                                    SwitchCaseItemSyntax(
                                      pattern: ExpressionPatternSyntax(
                                        expression: MemberAccessExprSyntax(
                                          period: .periodToken(),
                                          declName: DeclReferenceExprSyntax(baseName: .identifier(value.camelCased()))
                                        ))
                                    )
                                  ],
                                  colon: .colonToken()
                                )),
                              statements: CodeBlockItemListSyntax([
                                CodeBlockItemSyntax(
                                  item: CodeBlockItemSyntax.Item(
                                    StringLiteralExprSyntax(
                                      openingQuote: .stringQuoteToken(),
                                      segments: StringLiteralSegmentListSyntax([
                                        StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(value)))
                                      ]),
                                      closingQuote: .stringQuoteToken()
                                    )))
                              ])
                            )
                          }
                          SwitchCaseSyntax(
                            label: SwitchCaseSyntax.Label(
                              SwitchCaseLabelSyntax(
                                caseItems: [
                                  SwitchCaseItemSyntax(
                                    pattern: PatternSyntax(
                                      ValueBindingPatternSyntax(
                                        bindingSpecifier: .keyword(.let),
                                        pattern: PatternSyntax(
                                          ExpressionPatternSyntax(
                                            expression: FunctionCallExprSyntax(
                                              callee: MemberAccessExprSyntax(
                                                period: .periodToken(),
                                                declName: DeclReferenceExprSyntax(baseName: .identifier("_other"))
                                              )
                                            ) {
                                              LabeledExprSyntax(expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("value"))))
                                            }
                                          ))
                                      )))
                                ],
                                colon: .colonToken()
                              )),
                            statements: CodeBlockItemListSyntax([
                              CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(DeclReferenceExprSyntax(baseName: .identifier("value"))))
                            ])
                          )
                        }
                      )
                    ))
                ])),
            )
          )
        ])
      )
      decodableInitializerDeclSyntax(leadingTrivia: .newlines(2)) {
        VariableDeclSyntax(
          bindingSpecifier: .keyword(.let),
          bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("rawValue"))),
              initializer: InitializerClauseSyntax(
                equal: .equalToken(),
                value: TryExprSyntax(
                  expression: FunctionCallExprSyntax(
                    callee: DeclReferenceExprSyntax(baseName: .identifier("String"))
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("from"),
                      colon: .colonToken(),
                      expression: DeclReferenceExprSyntax(baseName: .identifier("decoder"))
                    )
                  }
                )
              )
            )
          ])
        )
        SequenceExprSyntax {
          DeclReferenceExprSyntax(baseName: .keyword(.self))
          AssignmentExprSyntax(equal: .equalToken())
          FunctionCallExprSyntax(
            callee: DeclReferenceExprSyntax(baseName: .keyword(.Self))
          ) {
            LabeledExprSyntax(
              label: .identifier("rawValue"),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("rawValue"))
            )
          }
        }
      }
      encodableFunctionDeclSyntax(leadingTrivia: .newlines(2)) {
        TryExprSyntax(
          expression: FunctionCallExprSyntax(
            callee: ExprSyntax(
              MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("rawValue")),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
              ))
          ) {
            LabeledExprSyntax(
              label: .identifier("to"),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("encoder"))
            )
          }
        )
      }
    }
  }
}
