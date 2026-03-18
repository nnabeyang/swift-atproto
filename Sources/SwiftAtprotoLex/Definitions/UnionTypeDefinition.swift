import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct UnionTypeDefinition: Codable, SwiftCodeGeneratable {
  var type: FieldType { .union }
  let description: String?
  let refs: [String]
  let closed: Bool?

  func generateDeclaration(
    leadingTrivia: Trivia?, ts: TypeSchema, name: String, type typeName: String,
    defMap: ExtDefMap, generate: GenerateOption
  ) -> any DeclSyntaxProtocol {
    var tss = [TypeSchema]()
    for ref in refs {
      let refName: String =
        if ref.first == "#" {
          "\(ts.id)\(ref)"
        } else {
          ref
        }
      guard let cts = defMap[refName] else {
        fatalError("no such ref: \(refName)")
      }
      tss.append(cts.type)
    }

    return EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.indirect)),
      ],
      name: .init(stringLiteral: name),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["Codable", "Hashable", "Sendable"])
    ) {
      for cts in tss {
        let id = cts.defName == "main" ? cts.id : #"\#(cts.id)#\#(cts.defName)"#
        let tn: TypeSyntaxProtocol =
          cts.prefix == ts.prefix
          ? IdentifierTypeSyntax(name: .identifier(cts.typeName.escapedSwiftKeyword))
          : MemberTypeSyntax(
            baseType: IdentifierTypeSyntax(name: .identifier(Lex.structNameFor(prefix: cts.prefix))),
            period: .periodToken(),
            name: .identifier(cts.typeName.escapedSwiftKeyword)
          )

        EnumCaseDeclSyntax {
          EnumCaseElementSyntax(
            name: .identifier(Lex.caseNameFromId(id: id, prefix: ts.prefix)),
            parameterClause: EnumCaseParameterClauseSyntax(
              parameters: [EnumCaseParameterSyntax(type: tn)]
            )
          )
        }
      }

      EnumCaseDeclSyntax {
        EnumCaseElementSyntax(
          name: .identifier("_other"),
          parameterClause: EnumCaseParameterClauseSyntax(
            leftParen: .leftParenToken(),
            parameters: EnumCaseParameterListSyntax([
              EnumCaseParameterSyntax(stringLiteral: "UnknownRecord")
            ]),
            rightParen: .rightParenToken()
          )
        )
      }
      EnumDeclSyntax(
        leadingTrivia: .newlines(2),
        name: "CodingKeys",
        inheritanceClause: InheritanceClauseSyntax(typeNames: ["String", "CodingKey"])
      ) {
        EnumCaseDeclSyntax {
          EnumCaseElementSyntax(
            name: "type",
            rawValue: InitializerClauseSyntax(
              value: StringLiteralExprSyntax(content: "$type")
            ))
        }
      }
      decodableInitializerDeclSyntax(leadingTrivia: .newlines(2)) {
        VariableDeclSyntax(
          bindingSpecifier: .keyword(.let)
        ) {
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
            initializer: InitializerClauseSyntax(
              value: TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                    name: .identifier("container")
                  )
                ) {
                  LabeledExprSyntax(
                    label: "keyedBy", colon: .colonToken(),
                    expression: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                      name: .keyword(.self)
                    ))
                }
              )
            )
          )
        }

        VariableDeclSyntax(
          bindingSpecifier: .keyword(.let)
        ) {
          PatternBindingSyntax(
            pattern: PatternSyntax("type"),
            initializer: InitializerClauseSyntax(
              value: TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                    name: .identifier("decode")
                  )
                ) {
                  LabeledExprSyntax(
                    expression: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("String")),
                      name: .keyword(.self)
                    ))
                  LabeledExprSyntax(label: "forKey", colon: .colonToken(), expression: MemberAccessExprSyntax(name: "type"))
                }
              )
            )
          )
        }

        SwitchExprSyntax(subject: ExprSyntax("type")) {
          for cts in tss {
            let id = cts.defName == "main" ? cts.id : #"\#(cts.id)#\#(cts.defName)"#
            SwitchCaseSyntax(
              label: .case(
                .init(caseItems: [
                  .init(pattern: ExpressionPatternSyntax(expression: StringLiteralExprSyntax(content: id)))
                ])
              )
            ) {
              SequenceExprSyntax {
                DeclReferenceExprSyntax(baseName: .keyword(.self))
                AssignmentExprSyntax()
                TryExprSyntax(
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(
                      name: .identifier(Lex.caseNameFromId(id: id, prefix: ts.prefix))
                    )
                  ) {
                    LabeledExprSyntax(
                      expression: FunctionCallExprSyntax(
                        callee: MemberAccessExprSyntax(
                          name: .keyword(.`init`)
                        )
                      ) {
                        LabeledExprSyntax(label: "from", colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("decoder")))
                      })
                  }
                )
              }
            }
          }
          SwitchCaseSyntax(label: .default(.init())) {
            SequenceExprSyntax {
              DeclReferenceExprSyntax(baseName: .keyword(.self))
              AssignmentExprSyntax()
              TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: ExprSyntax("._other")
                ) {
                  LabeledExprSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: ExprSyntax(".init")
                    ) {
                      LabeledExprSyntax(label: "from", colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("decoder")))
                    })
                }
              )
            }
          }
        }
      }
      encodableFunctionDeclSyntax(leadingTrivia: .newlines(2)) {
        VariableDeclSyntax(
          bindingSpecifier: .keyword(.var)
        ) {
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
            initializer: InitializerClauseSyntax(
              value: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("encoder")),
                  name: .identifier("container")
                )
              ) {
                LabeledExprSyntax(
                  label: "keyedBy", colon: .colonToken(),
                  expression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                    name: .keyword(.self)
                  ))
              }
            )
          )
        }

        SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
          for cts in tss {
            let id = cts.defName == "main" ? cts.id : #"\#(cts.id)#\#(cts.defName)"#
            SwitchCaseSyntax(
              label: .case(
                .init(caseItems: [
                  .init(
                    pattern: ValueBindingPatternSyntax(
                      bindingSpecifier: .keyword(.let),
                      pattern: ExpressionPatternSyntax(
                        expression: FunctionCallExprSyntax(
                          callee: MemberAccessExprSyntax(name: .identifier(Lex.caseNameFromId(id: id, prefix: ts.prefix)))
                        ) {
                          .init(
                            expression: PatternExprSyntax(
                              pattern: IdentifierPatternSyntax(identifier: .identifier("value"))
                            )
                          )
                        }
                      )
                    ))
                ])
              )
            ) {
              TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                  )
                ) {
                  LabeledExprSyntax(
                    expression: StringLiteralExprSyntax(
                      openingQuote: .stringQuoteToken(),
                      segments: StringLiteralSegmentListSyntax([
                        StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(id)))
                      ]),
                      closingQuote: .stringQuoteToken()
                    )
                  )
                  LabeledExprSyntax(
                    label: .identifier("forKey"),
                    colon: .colonToken(),
                    expression: MemberAccessExprSyntax(
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .identifier("type"))
                    )
                  )
                }
              )
              TryExprSyntax(
                expression: ExprSyntax(
                  FunctionCallExprSyntax(
                    callee: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("value"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                      ))
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("to"),
                      colon: .colonToken(),
                      expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("encoder")))
                    )
                  }
                )
              )
            }
          }
          SwitchCaseSyntax(
            label: .case(
              .init(caseItems: [
                .init(
                  pattern: ValueBindingPatternSyntax(
                    bindingSpecifier: .keyword(.let),
                    pattern: ExpressionPatternSyntax(
                      expression: FunctionCallExprSyntax(
                        callee: MemberAccessExprSyntax(name: .identifier("_other"))
                      ) {
                        .init(
                          expression: PatternExprSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("value"))
                          )
                        )
                      }
                    )
                  ))
              ])
            )
          ) {
            TryExprSyntax(
              expression: ExprSyntax(
                FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("value")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                  )
                ) {
                  LabeledExprSyntax(
                    label: .identifier("to"),
                    colon: .colonToken(),
                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("encoder")))
                  )
                })
            )
          }
        }
      }
    }
  }
}
