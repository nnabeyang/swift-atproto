import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension Lex {
  static func genXRPCAPIProtocolFile(for schemasMap: [String: [Schema]], defMap: ExtDefMap) -> String {
    var procedureTypes = [(key: String, prefix: String, value: TypeSchema, def: ProcedureTypeDefinition)]()
    for schemas in schemasMap {
      for schema in schemas.value {
        if let main = schema.defs["main"], case .procedure(let def) = main.type {
          let prefix = Lex.structNameFor(prefix: main.prefix)
          procedureTypes.append((Self.nameFromId(id: schema.id, prefix: schema.prefix), prefix, main, def))
        }
      }
    }
    procedureTypes = procedureTypes.sorted(by: { $0.value.id < $1.value.id })
    let src = SourceFileSyntax(
      leadingTrivia: fileHeader,
      statementsBuilder: {
        ImportDeclSyntax(
          path: [ImportPathComponentSyntax(name: "SwiftAtproto")]
        )
        ImportDeclSyntax(
          path: [ImportPathComponentSyntax(name: "HTTPTypes")]
        )
        ImportDeclSyntax(
          path: [ImportPathComponentSyntax(name: "Foundation")]
        )
        ImportDeclSyntax(
          attributes: AttributeListSyntax {
            AttributeSyntax(
              atSign: .atSignToken(),
              attributeName: IdentifierTypeSyntax(name: .identifier("_spi")),
              leftParen: .leftParenToken(),
              arguments: AttributeSyntax.Arguments([
                LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("Generated"))))
              ]),
              rightParen: .rightParenToken()
            )
          },
          path: [
            ImportPathComponentSyntax(name: .identifier("OpenAPIRuntime"))
          ],
          trailingTrivia: .newlines(2)
        )
        genXRPCAPIProtocol(for: procedureTypes)
        genXRPCExtension(for: procedureTypes)
        genUnversalServerExtension(for: procedureTypes, defMap: defMap)
      },
      trailingTrivia: .newlines(2))
    return src.formatted().description
  }

  private static func genXRPCAPIProtocol(leadingTrivia _: Trivia? = nil, for procedureTypes: [(key: String, prefix: String, value: TypeSchema, def: ProcedureTypeDefinition)]) -> ProtocolDeclSyntax {
    ProtocolDeclSyntax(
      leadingTrivia: nil,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier("XRPCAPIProtocol"),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable"])
    ) {
      for (key, _, scheme, _) in procedureTypes {
        genXRPCFunctionDeclSyntax(key: key, scheme: scheme)
      }
    }
  }

  private static func genXRPCExtension(leadingTrivia: Trivia? = nil, for procedureTypes: [(key: String, prefix: String, value: TypeSchema, def: ProcedureTypeDefinition)]) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
      extendedType: IdentifierTypeSyntax(name: .identifier("XRPCAPIProtocol"))
    ) {
      for (key, prefix, _, _) in procedureTypes {
        makeXRPCMethodStub(key: key, prefix: prefix)
      }
      genRegisterHandlers(for: procedureTypes)
    }
  }

  private static func makeXRPCMethodStub(leadingTrivia: Trivia? = nil, key: String, prefix: String) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      leadingTrivia: .spaces(2),
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .identifier("\(prefix)_\(key)"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          FunctionParameterSyntax(
            firstName: .wildcardToken(),
            secondName: .identifier("input"),
            colon: .colonToken(),
            type: MemberTypeSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input")])
          )
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: .keyword(.async),
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: ReturnClauseSyntax(
          type: MemberTypeSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Output")])
        )
      )
    ) {
      FunctionCallExprSyntax(
        callee: MemberAccessExprSyntax(
          leadingTrivia: .newline,
          declName: DeclReferenceExprSyntax(baseName: .identifier("undocumented"))
        )
      ) {
        LabeledExprSyntax(
          label: .identifier("statusCode"),
          colon: .colonToken(),
          expression: IntegerLiteralExprSyntax(literal: .integerLiteral("501")),
        )
        LabeledExprSyntax(
          expression: FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))))
        )
      }
      .with(\.leadingTrivia, .spaces(4))
    }
    .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: [.spaces(2)]))
    .with(\.trailingTrivia, .newlines(2))
  }

  private static func genXRPCFunctionDeclSyntax(leadingTrivia: Trivia? = nil, key: String, scheme: TypeSchema) -> FunctionDeclSyntax {
    let prefix = Lex.structNameFor(prefix: scheme.prefix)
    return FunctionDeclSyntax(
      leadingTrivia: [.newlines(1), .spaces(2)],
      name: .identifier("\(prefix)_\(key)"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(
          leftParen: .leftParenToken(),
          parameters: [
            FunctionParameterSyntax(
              firstName: .wildcardToken(),
              secondName: .identifier("input"),
              colon: .colonToken(),
              type: MemberTypeSyntax(
                baseType: MemberTypeSyntax(
                  baseType: IdentifierTypeSyntax(name: .identifier(prefix)),
                  period: .periodToken(),
                  name: .identifier(key)
                ),
                period: .periodToken(),
                name: .identifier("Input")
              )
            )
          ],
          rightParen: .rightParenToken()
        ),
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: .keyword(.async),
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: ReturnClauseSyntax(
          arrow: .arrowToken(),
          type: MemberTypeSyntax(
            baseType: MemberTypeSyntax(
              baseType: IdentifierTypeSyntax(name: .identifier(prefix)),
              period: .periodToken(),
              name: .identifier(key)
            ),
            period: .periodToken(),
            name: .identifier("Output")
          )
        )
      )
    )
  }

  private static func makeHandlerRegistration(leadingTrivia: Trivia? = nil, prefix: String, type: String) -> TryExprSyntax {
    TryExprSyntax(
      leadingTrivia: leadingTrivia,
      expression: FunctionCallExprSyntax(
        callee: MemberAccessExprSyntax(parts: [.identifier("transport"), .identifier("register")])
      ) {
        LabeledExprSyntax(
          leadingTrivia: [.newlines(1), .spaces(6)],
          expression: ClosureExprSyntax(rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])) {
            TryExprSyntax(
              leadingTrivia: [.newlines(1), .spaces(8)],
              expression: AwaitExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(parts: [.identifier("server"), .identifier("\(prefix)_\(type)")])
                ) {
                  for (i, label) in ["request", "body", "metadata"].enumerated() {
                    LabeledExprSyntax(
                      label: .identifier(label, leadingTrivia: [.newlines(1), .spaces(10)]),
                      colon: .colonToken(),
                      expression: DeclReferenceExprSyntax(baseName: .dollarIdentifier("$\(i)")),
                    )
                  }
                }
                .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(8)]))
              )
            )
          }
          .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(6)]))
        )
        LabeledExprSyntax(
          label: .identifier("method", leadingTrivia: [.newlines(1), .spaces(6)]),
          colon: .colonToken(),
          expression: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier("post")))
        )
        LabeledExprSyntax(
          label: .identifier("path", leadingTrivia: [.newlines(1), .spaces(6)]),
          colon: .colonToken(),
          expression: FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(parts: [.identifier("server"), .identifier("apiPathComponentsWithServerPrefix")])
          ) {
            LabeledExprSyntax(
              expression: StringLiteralExprSyntax {
                StringSegmentSyntax(content: .stringSegment("/"))
                ExpressionSegmentSyntax {
                  LabeledExprSyntax(
                    expression: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(type), .identifier("id")])
                  )
                }
                StringSegmentSyntax(content: .stringSegment(""))
              }
            )
          }
        )
      }
      .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(4)]))
    )
  }

  private static func genRegisterHandlers(leadingTrivia: Trivia? = nil, for procedureTypes: [(key: String, prefix: String, value: TypeSchema, def: ProcedureTypeDefinition)]) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      leadingTrivia: .spaces(2),
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier("registerHandlers"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(
          leftParen: .leftParenToken(),
          rightParen: .rightParenToken(leadingTrivia: [.newlines(1), .spaces(2)])
        ) {
          FunctionParameterSyntax(
            leadingTrivia: [.newlines(1), .spaces(4)],
            firstName: .identifier("on"),
            secondName: .identifier("transport"),
            colon: .colonToken(),
            type: TypeSyntax(
              SomeOrAnyTypeSyntax(
                someOrAnySpecifier: .keyword(.any),
                constraint: TypeSyntax(IdentifierTypeSyntax(name: .identifier("ServerTransport")))
              ))
          )
          FunctionParameterSyntax(
            leadingTrivia: [.newlines(1), .spaces(4)],
            firstName: .identifier("serverURL"),
            colon: .colonToken(),
            type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("URL"))),
            defaultValue: InitializerClauseSyntax(
              equal: .equalToken(),
              value: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier("defaultOpenAPIServerURL")))
            )
          )
          FunctionParameterSyntax(
            leadingTrivia: [.newlines(1), .spaces(4)],
            firstName: .identifier("configuration"),
            colon: .colonToken(),
            type: IdentifierTypeSyntax(name: .identifier("Configuration")),
            defaultValue: InitializerClauseSyntax(
              equal: .equalToken(),
              value: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`)))
              )
            )
          )
          FunctionParameterSyntax(
            leadingTrivia: [.newlines(1), .spaces(4)],
            firstName: .identifier("middlewares"),
            colon: .colonToken(),
            type: ArrayTypeSyntax(
              element: SomeOrAnyTypeSyntax(
                someOrAnySpecifier: .keyword(.any),
                constraint: IdentifierTypeSyntax(name: .identifier("ServerMiddleware"))
              ),
            ),
            defaultValue: InitializerClauseSyntax(
              equal: .equalToken(),
              value: ArrayExprSyntax {}
            )
          )
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
      )
    ) {
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let, leadingTrivia: [.newlines(1), .spaces(4)])
      ) {
        PatternBindingSyntax(
          pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("server"))),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: FunctionCallExprSyntax(
              callee: DeclReferenceExprSyntax(baseName: .identifier("UniversalServer"))
            ) {
              LabeledExprSyntax(
                label: .identifier("serverURL", leadingTrivia: [.newlines(1), .spaces(6)]),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("serverURL")),
              )
              LabeledExprSyntax(
                label: .identifier("handler", leadingTrivia: [.newlines(1), .spaces(6)]),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .keyword(.self)),
              )
              LabeledExprSyntax(
                label: .identifier("configuration", leadingTrivia: [.newlines(1), .spaces(6)]),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("configuration"))
              )
              LabeledExprSyntax(
                label: .identifier("middlewares", leadingTrivia: [.newlines(1), .spaces(6)]),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("middlewares"))
              )
            }
            .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(4)]))
          )
        )
      }

      for (type, prefix, _, _) in procedureTypes {
        makeHandlerRegistration(leadingTrivia: .spaces(4), prefix: prefix, type: type)
      }
    }
    .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: [.spaces(2)]))
  }

  private static func genUnversalServerExtension(
    leadingTrivia: Trivia? = nil, for procedureTypes: [(key: String, prefix: String, value: TypeSchema, def: ProcedureTypeDefinition)],
    defMap: ExtDefMap
  ) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
      extendedType: IdentifierTypeSyntax(name: .identifier("UniversalServer")),
      genericWhereClause: GenericWhereClauseSyntax(
        requirements: GenericRequirementListSyntax([
          GenericRequirementSyntax(
            requirement: GenericRequirementSyntax.Requirement(
              ConformanceRequirementSyntax(
                leftType: IdentifierTypeSyntax(name: .identifier("APIHandler")),
                colon: .colonToken(),
                rightType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("XRPCAPIProtocol")))
              )))
        ])
      )
    ) {
      for (key, prefix, schema, def) in procedureTypes {
        makeHandlerMethod(key: key, prefix: prefix, schema: schema, def: def, defMap: defMap)
      }
    }
  }

  private static func makeHandlerMethod(leadingTrivia: Trivia? = nil, key: String, prefix: String, schema: TypeSchema, def: ProcedureTypeDefinition, defMap: ExtDefMap) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      leadingTrivia: .spaces(2),
      name: .identifier("\(prefix)_\(key)"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          FunctionParameterSyntax(
            firstName: .identifier("request", leadingTrivia: [.newlines(1), .spaces(4)]),
            colon: .colonToken(),
            type: MemberTypeSyntax(parts: [.identifier("HTTPTypes"), .identifier("HTTPRequest")])
          )
          FunctionParameterSyntax(
            firstName: .identifier("body", leadingTrivia: [.newlines(1), .spaces(4)]),
            colon: .colonToken(),
            type: OptionalTypeSyntax(
              wrappedType: MemberTypeSyntax(
                baseType: IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime")),
                period: .periodToken(),
                name: .identifier("HTTPBody")
              ),
              questionMark: .postfixQuestionMarkToken()
            )
          )
          FunctionParameterSyntax(
            firstName: .identifier("metadata", leadingTrivia: [.newlines(1), .spaces(4)]),
            colon: .colonToken(),
            type: MemberTypeSyntax(
              baseType: IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime")),
              period: .periodToken(),
              name: .identifier("ServerRequestMetadata")
            )
          )
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: .keyword(.async),
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: ReturnClauseSyntax(
          type: TupleTypeSyntax(
            elements: TupleTypeElementListSyntax {
              TupleTypeElementSyntax(
                type: MemberTypeSyntax(
                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("HTTPTypes"))),
                  period: .periodToken(),
                  name: .identifier("HTTPResponse")
                )
              )
              TupleTypeElementSyntax(
                type: OptionalTypeSyntax(
                  wrappedType: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime"))),
                      period: .periodToken(),
                      name: .identifier("HTTPBody")
                    )),
                  questionMark: .postfixQuestionMarkToken()
                ))
            }
          )
        )
      )
    ) {
      TryExprSyntax(
        leadingTrivia: [.newlines(1), .spaces(6)],
        expression: AwaitExprSyntax(
          expression: FunctionCallExprSyntax(
            callee: DeclReferenceExprSyntax(baseName: .identifier("handle"))
          ) {
            LabeledExprSyntax(
              label: .identifier("request", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("request")),
            )
            LabeledExprSyntax(
              label: .identifier("requestBody", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("body"))
            )
            LabeledExprSyntax(
              label: .identifier("metadata", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("metadata"))
            )
            LabeledExprSyntax(
              label: .identifier("forOperation", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("id")])
            )
            LabeledExprSyntax(
              label: .identifier("using", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: ClosureExprSyntax {
                FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    leadingTrivia: [.newlines(1), .spaces(10)],
                    parts: [.identifier("APIHandler"), .identifier("\(prefix)_\(key)")]
                  )
                ) {
                  LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .dollarIdentifier("$0")))
                }
              }
              .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)]))
            )
            LabeledExprSyntax(
              label: .identifier("deserializer", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: makeDeserializerExpr(key: key, prefix: prefix, schema: schema, def: def, defMap: defMap)
            )
            LabeledExprSyntax(
              label: .identifier("serializer", leadingTrivia: [.newlines(1), .spaces(8)]),
              colon: .colonToken(),
              expression: makeSerializerExpr()
            )
          }
          .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(6)]))
        )
      )
    }
    .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(2)]))
  }

  /// `deserializer`
  private static func makeDeserializerExpr(key: String, prefix: String, schema: TypeSchema, def: ProcedureTypeDefinition, defMap: ExtDefMap) -> ClosureExprSyntax {
    ClosureExprSyntax(signaturesBuilder: {
      ClosureShorthandParameterSyntax(name: .identifier("request"))
      ClosureShorthandParameterSyntax(name: .identifier("requestBody"))
      ClosureShorthandParameterSyntax(name: .identifier("metadata"))
    }) {
      VariableDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        bindingSpecifier: .keyword(.let)
      ) {
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .identifier("headers")),
          typeAnnotation: TypeAnnotationSyntax(
            colon: .colonToken(),
            type: MemberTypeSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input"), .identifier("Headers")])
          ),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`)))
            ) {
              LabeledExprSyntax(
                label: .identifier("accept"),
                colon: .colonToken(),
                expression: TryExprSyntax(
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(parts: [
                      .identifier("converter"),
                      .identifier("extractAcceptHeaderIfPresent"),
                    ])
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("in"),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(parts: [.identifier("request"), .identifier("headerFields")])
                    )
                  })
              )
            }
          )
        )
      }
      VariableDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("contentType"))),
            initializer: InitializerClauseSyntax(
              equal: .equalToken(),
              value: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(parts: [.identifier("converter"), .identifier("extractContentTypeIfPresent")])
              ) {
                LabeledExprSyntax(
                  label: .identifier("in"),
                  colon: .colonToken(),
                  expression: MemberAccessExprSyntax(parts: [.identifier("request"), .identifier("headerFields")])
                )
              }
            )
          )
        ])
      )
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let, leadingTrivia: [.newlines(1), .spaces(10)]),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("body")),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: MemberTypeSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input"), .identifier("Body")])
            )
          )
        ])
      )
      genChosenContentType(key: key, def: def, prefix: prefix)
      genInputBodySwitch(key: key, schema: schema, def: def, prefix: prefix, defMap: defMap)
      ReturnStmtSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        expression: FunctionCallExprSyntax(
          callee: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input")])
        ) {
          LabeledExprSyntax(
            leadingTrivia: [.newlines(1), .spaces(12)],
            label: .identifier("headers"),
            colon: .colonToken(),
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("headers"))),
          )
          LabeledExprSyntax(
            leadingTrivia: [.newlines(1), .spaces(12)],
            label: .identifier("body"),
            colon: .colonToken(),
            expression: DeclReferenceExprSyntax(baseName: .identifier("body"))
          )
        }
        .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(10)]))
      )
    }
    .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)]))
  }
  /// `serializer`
  private static func makeSerializerExpr() -> ClosureExprSyntax {
    ClosureExprSyntax(signaturesBuilder: {
      ClosureShorthandParameterSyntax(name: .identifier("output"))
      ClosureShorthandParameterSyntax(name: .identifier("request"))
    }) {
      SwitchExprSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        subject: DeclReferenceExprSyntax(baseName: .identifier("output")),
      ) {
        SwitchCaseSyntax(
          label: SwitchCaseSyntax.Label(
            SwitchCaseLabelSyntax(
              leadingTrivia: [.newlines(1), .spaces(10)]) {
                SwitchCaseItemSyntax(
                  pattern: ExpressionPatternSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier("ok")))
                    ) {
                      LabeledExprSyntax(
                        expression: PatternExprSyntax(
                          pattern: ValueBindingPatternSyntax(
                            bindingSpecifier: .keyword(.let),
                            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("value")))
                          )))
                    }
                  ))
              }
          )
        ) {
          FunctionCallExprSyntax(
            callee: DeclReferenceExprSyntax(baseName: .identifier("suppressUnusedWarning"))
          ) {
            LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("value"))))
          }
          .with(\.leadingTrivia, [.newlines(1), .spaces(12)])
          VariableDeclSyntax(
            leadingTrivia: [.newlines(1), .spaces(12)],
            bindingSpecifier: .keyword(.var),
            bindings: [
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("response")),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(parts: [.identifier("HTTPTypes"), .identifier("HTTPResponse")])
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("soar_statusCode"),
                      colon: .colonToken(),
                      expression: IntegerLiteralExprSyntax(literal: .integerLiteral("201"))
                    )
                  }
                )
              )
            ]
          )
          FunctionCallExprSyntax(
            callee: DeclReferenceExprSyntax(baseName: .identifier("suppressMutabilityWarning", leadingTrivia: [.newlines(1), .spaces(10)]))
          ) {
            LabeledExprSyntax(
              expression: InOutExprSyntax(
                ampersand: .prefixAmpersandToken(),
                expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("response")))
              ))
          }
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.let, leadingTrivia: [.newlines(1), .spaces(12)]),
            bindings: PatternBindingListSyntax([
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("body")),
                typeAnnotation: TypeAnnotationSyntax(
                  colon: .colonToken(),
                  type: MemberTypeSyntax(
                    baseType: IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime")),
                    period: .periodToken(),
                    name: .identifier("HTTPBody")
                  )
                )
              )
            ])
          )
          ExpressionStmtSyntax(
            expression: SwitchExprSyntax(
              leadingTrivia: [.newlines(1), .spaces(12)],
              subject: MemberAccessExprSyntax(parts: [.identifier("value"), .identifier("body")])
            ) {
              SwitchCaseSyntax(
                label: SwitchCaseSyntax.Label(
                  SwitchCaseLabelSyntax(
                    leadingTrivia: [.newlines(1), .spaces(12)]) {
                      SwitchCaseItemSyntax(
                        pattern: ExpressionPatternSyntax(
                          expression: FunctionCallExprSyntax(
                            callee: MemberAccessExprSyntax(
                              period: .periodToken(),
                              declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                            )
                          ) {
                            LabeledExprSyntax(
                              expression: PatternExprSyntax(
                                pattern: ValueBindingPatternSyntax(
                                  bindingSpecifier: .keyword(.let),
                                  pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("value")))
                                )))
                          }
                        ))
                    }
                )
              ) {
                TryExprSyntax(
                  leadingTrivia: [.newlines(1), .spaces(14)],
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(parts: [
                      .identifier("converter"),
                      .identifier("validateAcceptIfPresent"),
                    ])
                  ) {
                    LabeledExprSyntax(
                      leadingTrivia: [.newlines(1), .spaces(16)],
                      expression: StringLiteralExprSyntax(content: "application/json")
                    )
                    LabeledExprSyntax(
                      label: .identifier("in", leadingTrivia: [.newlines(1), .spaces(16)]),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(parts: [.identifier("request"), .identifier("headerFields")])
                    )
                  }
                  .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(14)]))
                )
                SequenceExprSyntax {
                  DeclReferenceExprSyntax(
                    leadingTrivia: [.newlines(1), .spaces(14)],
                    baseName: .identifier("body"))
                  AssignmentExprSyntax(equal: .equalToken())
                  TryExprSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("converter"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("setResponseBodyAsJSON"))
                      )
                    ) {
                      LabeledExprSyntax(
                        leadingTrivia: [.newlines(1), .spaces(16)],
                        expression: DeclReferenceExprSyntax(baseName: .identifier("value")),
                      )
                      LabeledExprSyntax(
                        leadingTrivia: [.newlines(1), .spaces(16)],
                        label: .identifier("headerFields"),
                        colon: .colonToken(),
                        expression: InOutExprSyntax(
                          ampersand: .prefixAmpersandToken(),
                          expression: MemberAccessExprSyntax(parts: [.identifier("response"), .identifier("headerFields")])
                        )
                      )
                      LabeledExprSyntax(
                        leadingTrivia: [.newlines(1), .spaces(16)],
                        label: .identifier("contentType"),
                        colon: .colonToken(),
                        expression: StringLiteralExprSyntax(content: "application/json; charset=utf-8")
                      )
                    }
                    .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(14)]))
                  )
                }
              }
            }
            .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(12)]))
          )
          ReturnStmtSyntax(
            leadingTrivia: [.newlines(1), .spaces(12)],
            expression: ExprSyntax(
              TupleExprSyntax(
                leftParen: .leftParenToken(),
                elements: LabeledExprListSyntax([
                  LabeledExprSyntax(
                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("response"))),
                    trailingComma: .commaToken()
                  ),
                  LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("body")))),
                ]),
                rightParen: .rightParenToken()
              ))
          )
        }
        SwitchCaseSyntax(
          label: SwitchCaseSyntax.Label(
            SwitchCaseLabelSyntax(
              leadingTrivia: [.newlines(1), .spaces(10)]) {
                SwitchCaseItemSyntax(
                  pattern: ExpressionPatternSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("undocumented"))
                      )
                    ) {
                      LabeledExprSyntax(
                        expression: PatternExprSyntax(
                          pattern: PatternSyntax(
                            ValueBindingPatternSyntax(
                              bindingSpecifier: .keyword(.let),
                              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("statusCode")))
                            )))
                      )
                      LabeledExprSyntax(expression: ExprSyntax(DiscardAssignmentExprSyntax(wildcard: .wildcardToken())))
                    }
                  ))
              }
          )
        ) {
          ReturnStmtSyntax(
            leadingTrivia: [.newlines(1), .spaces(12)],
            expression: TupleExprSyntax {
              LabeledExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
                  )
                ) {
                  LabeledExprSyntax(
                    label: .identifier("soar_statusCode"),
                    colon: .colonToken(),
                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("statusCode")))
                  )
                },
                trailingComma: .commaToken()
              )
              LabeledExprSyntax(expression: NilLiteralExprSyntax(nilKeyword: .keyword(.nil)))
            }
          )
        }
      }
      .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(10)]))
    }
    .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)]))
  }

  private static func genChosenContentType(leadingTrivia: Trivia? = nil, key: String, def: ProcedureTypeDefinition, prefix: String) -> VariableDeclSyntax {
    VariableDeclSyntax(
      bindingSpecifier: .keyword(.let, leadingTrivia: [.newlines(1), .spaces(10)]),
      bindings: [
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .identifier("chosenContentType")),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: TryExprSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("converter")),
                  declName: DeclReferenceExprSyntax(baseName: .identifier("bestContentType"))
                )
              ) {
                LabeledExprSyntax(
                  leadingTrivia: [.newlines(1), .spaces(12)],
                  label: .identifier("received"),
                  colon: .colonToken(),
                  expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("contentType"))),
                )
                LabeledExprSyntax(
                  leadingTrivia: [.newlines(1), .spaces(12)],
                  label: .identifier("options"),
                  colon: .colonToken(),
                  expression: ArrayExprSyntax {
                    ArrayElementSyntax(
                      expression: StringLiteralExprSyntax(content: def.input?.encoding.rawValue ?? "application/json")
                    )
                  }
                )
              }
              .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(10)]))
            )
          )
        )
      ]
    )
  }

  private static func genInputBodySwitch(leadingTrivia: Trivia? = nil, key: String, schema: TypeSchema, def: ProcedureTypeDefinition, prefix: String, defMap: ExtDefMap) -> SwitchExprSyntax {
    SwitchExprSyntax(
      leadingTrivia: [.newlines(1), .spaces(10)],
      subject: DeclReferenceExprSyntax(baseName: .identifier("chosenContentType")),
      rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(10)])
    ) {
      SwitchCaseSyntax(
        label: SwitchCaseSyntax.Label(
          SwitchCaseLabelSyntax(
            leadingTrivia: [.newlines(1), .spaces(10)]) {
              SwitchCaseItemSyntax(
                pattern: ExpressionPatternSyntax(
                  expression: StringLiteralExprSyntax(content: def.input?.encoding.rawValue ?? "application/json")
                ))
            }
        )
      ) {
        SequenceExprSyntax {
          let asType = def.inputType(fname: key, defMap: defMap, prefix: prefix, binaryTypeName: "HTTPBody")
          DeclReferenceExprSyntax(baseName: .identifier("body", leadingTrivia: [.newlines(1), .spaces(12)]))
          AssignmentExprSyntax(equal: .equalToken())
          TryExprSyntax(
            expression: def.isBinary ? makeGetRequiredRequestBodyAsBinary() : makeGetRequiredRequestBodyAsJSON(asType: asType)
          )
        }
      }
      SwitchCaseSyntax(
        label: SwitchCaseSyntax.Label(
          SwitchDefaultLabelSyntax(
            leadingTrivia: [.newlines(1), .spaces(10)],
            colon: .colonToken()
          ))
      ) {
        FunctionCallExprSyntax(
          callee: DeclReferenceExprSyntax(baseName: .identifier("preconditionFailure", leadingTrivia: [.newlines(1), .spaces(12)]))
        ) {
          LabeledExprSyntax(
            expression: StringLiteralExprSyntax(
              openingQuote: .stringQuoteToken(),
              segments: StringLiteralSegmentListSyntax([
                StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("bestContentType chose an invalid content type.")))
              ]),
              closingQuote: .stringQuoteToken()
            ))
        }
      }
    }
  }

  private static func makeGetRequiredRequestBody(
    leadingTrivia: Trivia? = nil,
    asType: ExprSyntax,
    converterMethod: String,
    transformEnumCase: String,
    isAwait: Bool = false
  ) -> ExprSyntax {
    let functionCall = FunctionCallExprSyntax(
      callee: MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .identifier("converter")),
        declName: DeclReferenceExprSyntax(baseName: .identifier(converterMethod))
      )
    ) {
      LabeledExprSyntax(
        expression: MemberAccessExprSyntax(base: asType, declName: DeclReferenceExprSyntax(baseName: .keyword(.self)))
      )
      LabeledExprSyntax(
        label: .identifier("from", leadingTrivia: [.newlines(1), .spaces(14)]),
        colon: .colonToken(),
        expression: DeclReferenceExprSyntax(baseName: .identifier("requestBody"))
      )
      LabeledExprSyntax(
        label: .identifier("transforming", leadingTrivia: [.newlines(1), .spaces(14)]),
        colon: .colonToken(),
        expression: ClosureExprSyntax(signaturesBuilder: {
          ClosureShorthandParameterSyntax(name: .identifier("value"))
        }) {
          FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(
              leadingTrivia: [.newlines(1), .spaces(16)],
              declName: DeclReferenceExprSyntax(baseName: .identifier(transformEnumCase))
            )
          ) {
            LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("value")))
          }
        }
        .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(14)]))
      )
    }
    .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(12)]))
    let expression = isAwait ? ExprSyntax(AwaitExprSyntax(expression: functionCall)) : ExprSyntax(functionCall)
    return expression.with(\.leadingTrivia, leadingTrivia ?? [])
  }

  private static func makeGetRequiredRequestBodyAsJSON(leadingTrivia: Trivia? = nil, asType: ExprSyntax) -> ExprSyntax {
    makeGetRequiredRequestBody(
      leadingTrivia: leadingTrivia,
      asType: asType,
      converterMethod: "getRequiredRequestBodyAsJSON",
      transformEnumCase: "json",
      isAwait: true
    )
  }

  private static func makeGetRequiredRequestBodyAsBinary(leadingTrivia: Trivia? = nil) -> ExprSyntax {
    makeGetRequiredRequestBody(
      leadingTrivia: leadingTrivia,
      asType: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("HTTPBody"))),
      converterMethod: "getRequiredRequestBodyAsBinary",
      transformEnumCase: "binary",
      isAwait: false
    )
  }
}
