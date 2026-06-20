import Foundation
import SwiftBasicFormat
import SwiftSyntax
import SwiftSyntaxBuilder

extension Lex {
  static func genXRPCAPIProtocolFile(for schemasMap: [String: [Schema]], defMap: ExtDefMap) -> String {
    var methodTypes = [(key: String, prefix: String, value: TypeSchema, def: any HTTPAPITypeDefinition)]()
    for schemas in schemasMap {
      for schema in schemas.value {
        if let main = schema.defs["main"] {
          let prefix = Lex.structNameFor(prefix: main.prefix)
          switch main.type {
          case .procedure(let def as any HTTPAPITypeDefinition), .query(let def as any HTTPAPITypeDefinition):
            methodTypes.append((Self.nameFromId(id: schema.id, prefix: schema.prefix), prefix, main, def))
          default:
            break
          }
        }
      }
    }
    methodTypes = methodTypes.sorted(by: { $0.value.id < $1.value.id })
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
        genXRPCAPIProtocol(for: methodTypes)
        genXRPCExtension(for: methodTypes)
        genUnversalServerExtension(for: methodTypes, defMap: defMap)
      },
      trailingTrivia: .newlines(2))
    return src.formatted(using: BasicFormat(indentationWidth: .spaces(2))).description
  }

  private static func genXRPCAPIProtocol(leadingTrivia _: Trivia? = nil, for methodTypes: [(key: String, prefix: String, value: TypeSchema, def: any HTTPAPITypeDefinition)]) -> ProtocolDeclSyntax {
    ProtocolDeclSyntax(
      leadingTrivia: nil,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier("XRPCAPIProtocol"),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable"])
    ) {
      for (key, _, scheme, _) in methodTypes {
        genXRPCFunctionDeclSyntax(key: key, scheme: scheme)
      }
    }
  }

  private static func genXRPCExtension(leadingTrivia: Trivia? = nil, for methodTypes: [(key: String, prefix: String, value: TypeSchema, def: any HTTPAPITypeDefinition)]) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
      extendedType: IdentifierTypeSyntax(name: .identifier("XRPCAPIProtocol"))
    ) {
      for (key, prefix, _, _) in methodTypes {
        makeXRPCMethodStub(key: key, prefix: prefix)
      }
      genRegisterHandlers(for: methodTypes)
    }
  }

  private static func makeXRPCMethodStub(leadingTrivia: Trivia? = nil, key: String, prefix: String) -> FunctionDeclSyntax {
    let prefixIdent: [TokenSyntax] = Lex.structNameFor(prefix: prefix).split(separator: ".").map({ .identifier(String($0)) })
    return FunctionDeclSyntax(
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .identifier("\(Lex.enumNameFor(prefix: prefix))\(key)"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          FunctionParameterSyntax(
            firstName: .wildcardToken(),
            secondName: .identifier("input"),
            colon: .colonToken(),
            type: MemberTypeSyntax(parts: prefixIdent + [.identifier(key), .identifier("Input")])
          )
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: .keyword(.async),
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: ReturnClauseSyntax(
          type: MemberTypeSyntax(parts: prefixIdent + [.identifier(key), .identifier("Output")])
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
    }
    .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: .newline))
    .with(\.trailingTrivia, .newlines(2))
  }

  private static func genXRPCFunctionDeclSyntax(leadingTrivia: Trivia? = nil, key: String, scheme: TypeSchema) -> FunctionDeclSyntax {
    let prefix = Lex.structNameFor(prefix: scheme.prefix)
    return FunctionDeclSyntax(
      leadingTrivia: .newline,
      name: .identifier("\(Lex.enumNameFor(prefix: prefix))\(key)"),
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

  private static func genXRPCFunctionDeclSyntaxQuery(leadingTrivia: Trivia? = nil, key: String, scheme: TypeSchema) -> FunctionDeclSyntax {
    let prefix = Lex.structNameFor(prefix: scheme.prefix)
    return FunctionDeclSyntax(
      leadingTrivia: .newline,
      name: .identifier("\(Lex.enumNameFor(prefix: prefix))\(key)"),
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

  private static func makeHandlerRegistration(leadingTrivia: Trivia? = nil, prefix: String, type: String, method: String) -> TryExprSyntax {
    let prefixIdent: [TokenSyntax] = Lex.structNameFor(prefix: prefix).split(separator: ".").map({ .identifier(String($0)) })
    return TryExprSyntax(
      leadingTrivia: leadingTrivia,
      expression: FunctionCallExprSyntax(
        callee: MemberAccessExprSyntax(parts: [.identifier("transport"), .identifier("register")])
      ) {
        LabeledExprSyntax(
          leadingTrivia: .newline,
          expression: ClosureExprSyntax(rightBrace: .rightBraceToken(leadingTrivia: .newline)) {
            TryExprSyntax(
              leadingTrivia: .newline,
              expression: AwaitExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(parts: [.identifier("server"), .identifier("\(Lex.enumNameFor(prefix: prefix))\(type)")])
                ) {
                  for (i, label) in ["request", "body", "metadata"].enumerated() {
                    LabeledExprSyntax(
                      label: .identifier(label, leadingTrivia: .newline),
                      colon: .colonToken(),
                      expression: DeclReferenceExprSyntax(baseName: .dollarIdentifier("$\(i)")),
                    )
                  }
                }
                .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
              )
            )
          }
          .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
        )
        LabeledExprSyntax(
          label: .identifier("method", leadingTrivia: .newline),
          colon: .colonToken(),
          expression: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier(method)))
        )
        LabeledExprSyntax(
          label: .identifier("path", leadingTrivia: .newline),
          colon: .colonToken(),
          expression: FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(parts: [.identifier("server"), .identifier("apiPathComponentsWithServerPrefix")])
          ) {
            LabeledExprSyntax(
              expression: StringLiteralExprSyntax {
                StringSegmentSyntax(content: .stringSegment("/"))
                ExpressionSegmentSyntax {
                  LabeledExprSyntax(
                    expression: MemberAccessExprSyntax(parts: prefixIdent + [.identifier(type), .identifier("id")])
                  )
                }
                StringSegmentSyntax(content: .stringSegment(""))
              }
            )
          }
        )
      }
      .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
    )
  }

  private static func genRegisterHandlers(leadingTrivia: Trivia? = nil, for methodTypes: [(key: String, prefix: String, value: TypeSchema, def: any HTTPAPITypeDefinition)]) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier("registerHandlers"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(
          leftParen: .leftParenToken(),
          rightParen: .rightParenToken(leadingTrivia: .newline)
        ) {
          FunctionParameterSyntax(
            leadingTrivia: .newline,
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
            leadingTrivia: .newline,
            firstName: .identifier("serverURL"),
            colon: .colonToken(),
            type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("URL"))),
            defaultValue: InitializerClauseSyntax(
              equal: .equalToken(),
              value: MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier("defaultOpenAPIServerURL")))
            )
          )
          FunctionParameterSyntax(
            leadingTrivia: .newline,
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
            leadingTrivia: .newline,
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
        bindingSpecifier: .keyword(.let, leadingTrivia: .newline)
      ) {
        PatternBindingSyntax(
          pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("server"))),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: FunctionCallExprSyntax(
              callee: DeclReferenceExprSyntax(baseName: .identifier("UniversalServer"))
            ) {
              LabeledExprSyntax(
                label: .identifier("serverURL", leadingTrivia: .newline),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("serverURL")),
              )
              LabeledExprSyntax(
                label: .identifier("handler", leadingTrivia: .newline),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .keyword(.self)),
              )
              LabeledExprSyntax(
                label: .identifier("configuration", leadingTrivia: .newline),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("configuration"))
              )
              LabeledExprSyntax(
                label: .identifier("middlewares", leadingTrivia: .newline),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("middlewares"))
              )
            }
            .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
          )
        )
      }

      for (type, prefix, _, def) in methodTypes {
        let method: String =
          switch def {
          case is QueryTypeDefinition:
            "get"
          case is ProcedureTypeDefinition:
            "post"
          default:
            fatalError("unreachable")
          }
        makeHandlerRegistration(prefix: prefix, type: type, method: method)
      }
    }
    .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: .newline))
  }

  private static func genUnversalServerExtension(
    leadingTrivia: Trivia? = nil, for methodTypes: [(key: String, prefix: String, value: TypeSchema, def: any HTTPAPITypeDefinition)],
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
      for (key, prefix, schema, def) in methodTypes {
        makeHandlerMethod(key: key, prefix: prefix, schema: schema, def: def, defMap: defMap)
      }
    }
  }

  private static func makeHandlerMethod(leadingTrivia: Trivia? = nil, key: String, prefix: String, schema: TypeSchema, def: any HTTPAPITypeDefinition, defMap: ExtDefMap) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      name: .identifier("\(Lex.enumNameFor(prefix: prefix))\(key)"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          FunctionParameterSyntax(
            firstName: .identifier("request", leadingTrivia: .newline),
            colon: .colonToken(),
            type: MemberTypeSyntax(parts: [.identifier("HTTPTypes"), .identifier("HTTPRequest")])
          )
          FunctionParameterSyntax(
            firstName: .identifier("body", leadingTrivia: .newline),
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
            firstName: .identifier("metadata", leadingTrivia: .newline),
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
        leadingTrivia: .newline,
        expression: AwaitExprSyntax(
          expression: FunctionCallExprSyntax(
            callee: DeclReferenceExprSyntax(baseName: .identifier("handle"))
          ) {
            LabeledExprSyntax(
              label: .identifier("request", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("request")),
            )
            LabeledExprSyntax(
              label: .identifier("requestBody", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("body"))
            )
            LabeledExprSyntax(
              label: .identifier("metadata", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("metadata"))
            )
            LabeledExprSyntax(
              label: .identifier("forOperation", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("id")])
            )
            LabeledExprSyntax(
              label: .identifier("using", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: ClosureExprSyntax {
                FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    leadingTrivia: .newline,
                    parts: [.identifier("APIHandler"), .identifier("\(Lex.enumNameFor(prefix: prefix))\(key)")]
                  )
                ) {
                  LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .dollarIdentifier("$0")))
                }
              }
              .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
            )
            LabeledExprSyntax(
              label: .identifier("deserializer", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: makeDeserializerExpr(key: key, prefix: prefix, schema: schema, def: def, defMap: defMap)
            )
            LabeledExprSyntax(
              label: .identifier("serializer", leadingTrivia: .newline),
              colon: .colonToken(),
              expression: makeSerializerExpr()
            )
          }
          .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
        )
      )
    }
    .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: .newline))
  }

  /// `deserializer`
  private static func makeDeserializerExpr(key: String, prefix: String, schema: TypeSchema, def: any HTTPAPITypeDefinition, defMap: ExtDefMap) -> ClosureExprSyntax {
    switch def {
    case let def as ProcedureTypeDefinition:
      makeDeserializerExpr(key: key, prefix: prefix, schema: schema, def: def, defMap: defMap)
    case let def as QueryTypeDefinition:
      makeDeserializerExpr(key: key, prefix: prefix, schema: schema, def: def, defMap: defMap)
    default:
      fatalError("Unhandled definition type: \(def)")
    }
  }

  private static func makeDeserializerExpr(key: String, prefix: String, schema: TypeSchema, def: ProcedureTypeDefinition, defMap: ExtDefMap) -> ClosureExprSyntax {
    let hasInput = def.input != nil
    return ClosureExprSyntax(signaturesBuilder: {
      ClosureShorthandParameterSyntax(name: .identifier("request"))
      ClosureShorthandParameterSyntax(name: .identifier("requestBody"))
      ClosureShorthandParameterSyntax(name: .identifier("metadata"))
    }) {
      VariableDeclSyntax(
        leadingTrivia: .newline,
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
      if hasInput {
        VariableDeclSyntax(
          leadingTrivia: .newline,
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
          bindingSpecifier: .keyword(.let, leadingTrivia: .newline),
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
      }
      ReturnStmtSyntax(
        leadingTrivia: .newline,
        expression: FunctionCallExprSyntax(
          callee: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input")])
        ) {
          LabeledExprSyntax(
            leadingTrivia: .newline,
            label: .identifier("headers"),
            colon: .colonToken(),
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("headers"))),
          )
          if hasInput {
            LabeledExprSyntax(
              leadingTrivia: .newline,
              label: .identifier("body"),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .identifier("body"))
            )
          }
        }
        .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
      )
    }
    .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
  }

  private static func makeDeserializerExpr(key: String, prefix: String, schema: TypeSchema, def: QueryTypeDefinition, defMap: ExtDefMap) -> ClosureExprSyntax {
    return ClosureExprSyntax(signaturesBuilder: {
      ClosureShorthandParameterSyntax(name: .identifier("request"))
      ClosureShorthandParameterSyntax(name: .identifier("requestBody"))
      ClosureShorthandParameterSyntax(name: .identifier("metadata"))
    }) {
      for (i, (key, isRequired, type)) in def.params(ts: schema, fname: key, defMap: defMap, prefix: prefix).enumerated() {
        VariableDeclSyntax(
          leadingTrivia: .newline,
          bindingSpecifier: .keyword(.let)
        ) {
          PatternBindingSyntax(
            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("query\(i)"))),
            initializer: InitializerClauseSyntax(
              equal: .equalToken(),
              value: TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(parts: [
                    .identifier("converter"),
                    .identifier(isRequired ? "getRequiredQueryItemAsURI" : "getOptionalQueryItemAsURI"),
                  ])
                ) {
                  LabeledExprSyntax(
                    label: .identifier("in", leadingTrivia: .newline),
                    colon: .colonToken(),
                    expression: MemberAccessExprSyntax(parts: [.identifier("request"), .identifier("soar_query")])
                  )
                  LabeledExprSyntax(
                    label: .identifier("style", leadingTrivia: .newline),
                    colon: .colonToken(),
                    expression: MemberAccessExprSyntax(
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .identifier("form"))
                    )
                  )
                  LabeledExprSyntax(
                    label: .identifier("explode", leadingTrivia: .newline),
                    colon: .colonToken(),
                    expression: ExprSyntax(BooleanLiteralExprSyntax(literal: .keyword(.true)))
                  )
                  LabeledExprSyntax(
                    label: .identifier("name", leadingTrivia: .newline),
                    colon: .colonToken(),
                    expression: StringLiteralExprSyntax(content: key)
                  )
                  LabeledExprSyntax(
                    label: .identifier("as", leadingTrivia: .newline),
                    colon: .colonToken(),
                    expression: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: type,
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ))
                  )
                }
                .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
              )
            )
          )
        }
      }
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let, leadingTrivia: .newline)
      ) {
        PatternBindingSyntax(
          pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("query"))),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input"), .identifier("Query")])
            ) {
              for (i, (key, _)) in (def.parameters?.sortedProperties ?? []).enumerated() {
                LabeledExprSyntax(
                  label: .identifier(key),
                  colon: .colonToken(),
                  expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("query\(i)")))
                )
              }
            }
          )
        )
      }
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let, leadingTrivia: .newline)
      ) {
        PatternBindingSyntax(
          pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("headers"))),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input"), .identifier("Headers")])
            ) {
              LabeledExprSyntax(
                label: .identifier("accept"),
                colon: .colonToken(),
                expression: TryExprSyntax(
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(parts: [.identifier("converter"), .identifier("extractAcceptHeaderIfPresent")])
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("in"),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(parts: [.identifier("request"), .identifier("headerFields")])
                    )
                  }
                )
              )
            }
          )
        )
      }
      ReturnStmtSyntax(
        returnKeyword: .keyword(.return, leadingTrivia: .newline),
        expression: FunctionCallExprSyntax(
          callee: MemberAccessExprSyntax(parts: [.identifier(prefix), .identifier(key), .identifier("Input")])
        ) {
          LabeledExprSyntax(
            label: .identifier("query", leadingTrivia: .newline),
            colon: .colonToken(trailingTrivia: .space),
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("query"))),
            trailingComma: .commaToken()
          )
          LabeledExprSyntax(
            label: .identifier("headers", leadingTrivia: .newline),
            colon: .colonToken(trailingTrivia: .space),
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("headers")))
          )
        }
        .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
      )
    }
  }
  /// `serializer`
  private static func makeSerializerExpr() -> ClosureExprSyntax {
    ClosureExprSyntax(signaturesBuilder: {
      ClosureShorthandParameterSyntax(name: .identifier("output"))
      ClosureShorthandParameterSyntax(name: .identifier("request"))
    }) {
      SwitchExprSyntax(
        leadingTrivia: .newline,
        subject: DeclReferenceExprSyntax(baseName: .identifier("output")),
      ) {
        SwitchCaseSyntax(
          label: SwitchCaseSyntax.Label(
            SwitchCaseLabelSyntax(
              leadingTrivia: .newline
            ) {
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
          .with(\.leadingTrivia, .newline)
          VariableDeclSyntax(
            leadingTrivia: .newline,
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
            callee: DeclReferenceExprSyntax(baseName: .identifier("suppressMutabilityWarning", leadingTrivia: .newline))
          ) {
            LabeledExprSyntax(
              expression: InOutExprSyntax(
                ampersand: .prefixAmpersandToken(),
                expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("response")))
              ))
          }
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.let, leadingTrivia: .newline),
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
              leadingTrivia: .newline,
              subject: MemberAccessExprSyntax(parts: [.identifier("value"), .identifier("body")])
            ) {
              SwitchCaseSyntax(
                label: SwitchCaseSyntax.Label(
                  SwitchCaseLabelSyntax(
                    leadingTrivia: .newline
                  ) {
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
                  leadingTrivia: .newline,
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(parts: [
                      .identifier("converter"),
                      .identifier("validateAcceptIfPresent"),
                    ])
                  ) {
                    LabeledExprSyntax(
                      leadingTrivia: .newline,
                      expression: StringLiteralExprSyntax(content: "application/json")
                    )
                    LabeledExprSyntax(
                      label: .identifier("in", leadingTrivia: .newline),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(parts: [.identifier("request"), .identifier("headerFields")])
                    )
                  }
                  .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
                )
                SequenceExprSyntax {
                  DeclReferenceExprSyntax(
                    leadingTrivia: .newline,
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
                        leadingTrivia: .newline,
                        expression: DeclReferenceExprSyntax(baseName: .identifier("value")),
                      )
                      LabeledExprSyntax(
                        leadingTrivia: .newline,
                        label: .identifier("headerFields"),
                        colon: .colonToken(),
                        expression: InOutExprSyntax(
                          ampersand: .prefixAmpersandToken(),
                          expression: MemberAccessExprSyntax(parts: [.identifier("response"), .identifier("headerFields")])
                        )
                      )
                      LabeledExprSyntax(
                        leadingTrivia: .newline,
                        label: .identifier("contentType"),
                        colon: .colonToken(),
                        expression: StringLiteralExprSyntax(content: "application/json; charset=utf-8")
                      )
                    }
                    .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
                  )
                }
              }
            }
            .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
          )
          ReturnStmtSyntax(
            leadingTrivia: .newline,
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
              leadingTrivia: .newline
            ) {
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
            leadingTrivia: .newline,
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
      .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
    }
    .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
  }

  private static func genChosenContentType(leadingTrivia: Trivia? = nil, key: String, def: ProcedureTypeDefinition, prefix: String) -> VariableDeclSyntax {
    VariableDeclSyntax(
      bindingSpecifier: .keyword(.let, leadingTrivia: .newline),
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
                  leadingTrivia: .newline,
                  label: .identifier("received"),
                  colon: .colonToken(),
                  expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("contentType"))),
                )
                LabeledExprSyntax(
                  leadingTrivia: .newline,
                  label: .identifier("options"),
                  colon: .colonToken(),
                  expression: ArrayExprSyntax {
                    ArrayElementSyntax(
                      expression: StringLiteralExprSyntax(content: def.input?.encoding.rawValue ?? "application/json")
                    )
                  }
                )
              }
              .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
            )
          )
        )
      ]
    )
  }

  private static func genInputBodySwitch(leadingTrivia: Trivia? = nil, key: String, schema: TypeSchema, def: ProcedureTypeDefinition, prefix: String, defMap: ExtDefMap) -> SwitchExprSyntax {
    SwitchExprSyntax(
      leadingTrivia: .newline,
      subject: DeclReferenceExprSyntax(baseName: .identifier("chosenContentType")),
      rightBrace: .rightBraceToken(leadingTrivia: .newline)
    ) {
      SwitchCaseSyntax(
        label: SwitchCaseSyntax.Label(
          SwitchCaseLabelSyntax(
            leadingTrivia: .newline
          ) {
            SwitchCaseItemSyntax(
              pattern: ExpressionPatternSyntax(
                expression: StringLiteralExprSyntax(content: def.input?.encoding.rawValue ?? "application/json")
              ))
          }
        )
      ) {
        SequenceExprSyntax {
          let asType = def.inputType(fname: key, defMap: defMap, prefix: prefix, binaryTypeName: "HTTPBody")
          DeclReferenceExprSyntax(baseName: .identifier("body", leadingTrivia: .newline))
          AssignmentExprSyntax(equal: .equalToken())
          TryExprSyntax(
            expression: def.isBinary ? makeGetRequiredRequestBodyAsBinary() : makeGetRequiredRequestBodyAsJSON(asType: asType)
          )
        }
      }
      SwitchCaseSyntax(
        label: SwitchCaseSyntax.Label(
          SwitchDefaultLabelSyntax(
            leadingTrivia: .newline,
            colon: .colonToken()
          ))
      ) {
        FunctionCallExprSyntax(
          callee: DeclReferenceExprSyntax(baseName: .identifier("preconditionFailure", leadingTrivia: .newline))
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
        label: .identifier("from", leadingTrivia: .newline),
        colon: .colonToken(),
        expression: DeclReferenceExprSyntax(baseName: .identifier("requestBody"))
      )
      LabeledExprSyntax(
        label: .identifier("transforming", leadingTrivia: .newline),
        colon: .colonToken(),
        expression: ClosureExprSyntax(signaturesBuilder: {
          ClosureShorthandParameterSyntax(name: .identifier("value"))
        }) {
          FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(
              leadingTrivia: .newline,
              declName: DeclReferenceExprSyntax(baseName: .identifier(transformEnumCase))
            )
          ) {
            LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("value")))
          }
        }
        .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
      )
    }
    .with(\.rightParen, .rightParenToken(leadingTrivia: .newline))
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
