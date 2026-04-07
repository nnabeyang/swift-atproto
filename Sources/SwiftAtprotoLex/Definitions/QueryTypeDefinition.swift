import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct QueryTypeDefinition: HTTPAPITypeDefinition, SwiftCodeGeneratable {
  var type: FieldType { .query }
  let parameters: Parameters?
  let output: OutputType?
  let description: String?
  let errors: [ErrorResponse]?

  private enum CodingKeys: String, CodingKey {
    case type
    case parameters
    case output
    case input
    case description
    case errors
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    parameters = try container.decodeIfPresent(Parameters.self, forKey: .parameters, configuration: configuration)
    output = try container.decodeIfPresent(OutputType.self, forKey: .output, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    errors = try container.decodeIfPresent([ErrorResponse].self, forKey: .errors)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(output, forKey: .output)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(errors, forKey: .errors)
  }

  private func queries(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [PatternBindingSyntax] {
    var queries = [PatternBindingSyntax]()
    guard let parameters else { return queries }
    var required = [String: Bool]()
    for req in parameters.required ?? [] {
      required[req] = true
    }
    for (name, t) in parameters.sortedProperties {
      let isRequired = required[name] ?? false
      let tn: String
      if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
        tn = "\(prefix).\(fname)_\(name.titleCased())"
      } else {
        let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
        tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, dropPrefix: false)
      }
      let type: TypeSyntax
      if isRequired {
        type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(tn)))
      } else {
        type = TypeSyntax(
          OptionalTypeSyntax(
            wrappedType: IdentifierTypeSyntax(name: .identifier(tn)),
            questionMark: .postfixQuestionMarkToken()
          ))
      }
      queries.append(
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
          typeAnnotation: TypeAnnotationSyntax(
            colon: .colonToken(),
            type: type
          )))
    }
    return queries
  }

  func params(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [(key: String, isRequired: Bool, type: DeclReferenceExprSyntax)] {
    var queries = [(key: String, isRequired: Bool, type: DeclReferenceExprSyntax)]()
    guard let parameters else { return queries }
    var required = [String: Bool]()
    for req in parameters.required ?? [] {
      required[req] = true
    }
    for (name, t) in parameters.sortedProperties {
      let isRequired = required[name] ?? false
      let tn: String
      if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
        tn = "\(prefix).\(fname)_\(name.titleCased())"
      } else {
        let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
        tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, dropPrefix: false)
      }
      let type = DeclReferenceExprSyntax(baseName: .identifier(tn))
      queries.append((key: name, isRequired: isRequired, type: type))
    }
    return queries
  }

  func output(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> TokenSyntax {
    if let output {
      switch output.encoding {
      case .json, .jsonl:
        guard let schema = output.schema else {
          return .identifier("EmptyResponse")
        }
        let outname: String
        if case .ref(let def) = schema.type {
          (_, outname) = ts.namesFromRef(ref: def.ref, defMap: defMap)
        } else {
          outname = "\(fname)_Output"
        }
        return .identifier("\(prefix).\(outname)")
      case .text:
        return .identifier("String")
      case .cbor, .car, .any, .mp4:
        return .identifier("Data")
      }
    }
    return .identifier("EmptyResponse")
  }

  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [FunctionParameterSyntax] {
    var arguments = [FunctionParameterSyntax]()
    guard let parameters else { return arguments }
    var required = [String: Bool]()
    for req in parameters.required ?? [] {
      required[req] = true
    }
    for (name, t) in parameters.sortedProperties {
      let isRequired = required[name] ?? false
      let tn: String
      if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
        tn = "\(prefix).\(fname)_\(name.titleCased())"
      } else {
        let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
        tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, dropPrefix: false)
      }
      let type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(tn)))
      let defaultValue: InitializerClauseSyntax? =
        isRequired
        ? nil
        : InitializerClauseSyntax(
          equal: .equalToken(),
          value: NilLiteralExprSyntax()
        )
      arguments.append(
        .init(
          firstName: .identifier(name),
          type: isRequired
            ? type
            : TypeSyntax(OptionalTypeSyntax(wrappedType: type)), defaultValue: defaultValue))
    }
    return arguments
  }

  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol {
    if let parameters, !parameters.properties.isEmpty {
      var required = [String: Bool]()
      for req in parameters.required ?? [] {
        required[req] = true
      }
      return DictionaryExprSyntax {
        for (name, t) in parameters.sortedProperties {
          let ts = TypeSchema(id: id, prefix: prefix, defName: name, type: t)
          let tn = TypeSchema.paramNameForField(typeSchema: ts)
          let isRequired = required[name] ?? false
          let stringLiteral =
            if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
              isRequired ? ".\(tn)(\(name).rawValue)" : ".\(tn)(\(name)?.rawValue)"
            } else {
              ".\(tn)(\(name))"
            }
          DictionaryElementSyntax(
            key: StringLiteralExprSyntax(content: name),
            value: ExprSyntax(stringLiteral: stringLiteral)
          )
        }
      }
    } else {
      return NilLiteralExprSyntax()
    }
  }

  func generateDeclaration(leadingTrivia: SwiftSyntax.Trivia?, ts: TypeSchema, name: String, type: String, defMap: ExtDefMap, generate: GenerateOption) -> any DeclSyntaxProtocol {
    return EnumDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier(ts.typeName),
      inheritanceClause: InheritanceClauseSyntax {
        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("XRPCQuery")))
      }
    ) {
      VariableDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(2)],
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public)),
          DeclModifierSyntax(name: .keyword(.static)),
        ],
        bindingSpecifier: .keyword(.let)
      ) {
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .identifier("id")),
          initializer: InitializerClauseSyntax(
            equal: .equalToken(),
            value: StringLiteralExprSyntax(
              openingQuote: .stringQuoteToken(),
              segments: StringLiteralSegmentListSyntax([
                StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(type)))
              ]),
              closingQuote: .stringQuoteToken()
            )
          )
        )
      }
      TypeAliasDeclSyntax(
        modifiers: [DeclModifierSyntax(name: .keyword(.public, leadingTrivia: .newline))],
        name: .identifier("ResponseBody"),
        initializer: TypeInitializerClauseSyntax(
          equal: .equalToken(),
          value: IdentifierTypeSyntax(name: output(ts: ts, fname: name, defMap: defMap, prefix: Lex.structNameFor(prefix: ts.prefix)))
        )
      )
      genQueryInput(ts: ts, name: name, type: type, prefix: ts.prefix, defMap: defMap, generate: generate)
      if generate.contains(.server) {
        genQueryOutput(ts: ts, name: name, type: type, prefix: ts.prefix, defMap: defMap)
        genAcceptableContentType()
      }
      makeErrorDeclaration(leadingTrivia: [.newlines(1)], ts: ts, name: name, type: type)
    }
  }

  private func genQueryInput(ts: TypeSchema, name: String, type: String, prefix: String, defMap: ExtDefMap, generate: GenerateOption) -> StructDeclSyntax {
    let prefix = Lex.structNameFor(prefix: prefix)
    return StructDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier("Input"),
      inheritanceClause: InheritanceClauseSyntax {
        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("XRPCQueryInput")))
      }
    ) {
      StructDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(4)],
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        name: .identifier("Query"),
        inheritanceClause: InheritanceClauseSyntax {
          InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("XRPCInputQuery")))
        }
      ) {
        for query in queries(ts: ts, fname: name, defMap: defMap, prefix: prefix) {
          VariableDeclSyntax(
            leadingTrivia: [.newlines(1), .spaces(8)],
            modifiers: DeclModifierListSyntax([
              DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: [query]
          )
        }
        InitializerDeclSyntax(
          leadingTrivia: [.newlines(2), .spaces(8)],
          modifiers: [DeclModifierSyntax(name: .keyword(.public))],
          signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax {
              rpcArguments(ts: ts, fname: name, defMap: defMap, prefix: prefix)
            })
        ) {
          for (key, _) in parameters?.sortedProperties ?? [] {
            SequenceExprSyntax(leadingTrivia: [.newlines(1), .spaces(10)]) {
              MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier(key))
              )
              AssignmentExprSyntax(equal: .equalToken())
              DeclReferenceExprSyntax(baseName: .identifier(key))
            }
          }
        }
        VariableDeclSyntax(
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public))
          ]),
          bindingSpecifier: .keyword(.var),
          bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("asParameters"))),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: TypeSyntax(
                  OptionalTypeSyntax(
                    wrappedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Parameters"))),
                    questionMark: .postfixQuestionMarkToken()
                  ))
              ),
              accessorBlock: AccessorBlockSyntax(
                leftBrace: .leftBraceToken(),
                accessors: AccessorBlockSyntax.Accessors(
                  CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(
                      item: CodeBlockItemSyntax.Item(
                        rpcParams(id: ts.id, prefix: prefix)
                      ))
                  ])),
                rightBrace: .rightBraceToken(leadingTrivia: .newline)
              )
            )
          ])
        )
      }
      VariableDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(4)],
        modifiers: [DeclModifierSyntax(name: .keyword(.public))],
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("query")),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: TypeSyntax(
                MemberTypeSyntax(
                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Input"))),
                  period: .periodToken(),
                  name: .identifier("Query")
                ))
            )
          )
        ])
      )
      if generate.contains(.server) {
        StructDeclSyntax(
          leadingTrivia: [.newlines(1), .spaces(4)],
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public))
          ]),
          name: .identifier("Headers"),
          inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"]),
          memberBlock: MemberBlockSyntax(
            leftBrace: .leftBraceToken(),
            members: MemberBlockItemListSyntax([
              MemberBlockItemSyntax(
                decl: DeclSyntax(
                  VariableDeclSyntax(
                    modifiers: DeclModifierListSyntax([
                      DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(8)]))
                    ]),
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                      PatternBindingSyntax(
                        pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("accept"))),
                        typeAnnotation: TypeAnnotationSyntax(
                          colon: .colonToken(),
                          type: TypeSyntax(
                            ArrayTypeSyntax(
                              leftSquare: .leftSquareToken(),
                              element: TypeSyntax(
                                MemberTypeSyntax(
                                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime"))),
                                  period: .periodToken(),
                                  name: .identifier("AcceptHeaderContentType"),
                                  genericArgumentClause: GenericArgumentClauseSyntax(
                                    leftAngle: .leftAngleToken(),
                                    arguments: GenericArgumentListSyntax([
                                      GenericArgumentSyntax.create(argument: IdentifierTypeSyntax(name: .identifier("AcceptableContentType")))
                                    ]),
                                    rightAngle: .rightAngleToken()
                                  )
                                )),
                              rightSquare: .rightSquareToken()
                            ))
                        )
                      )
                    ])
                  ))),
              MemberBlockItemSyntax(
                decl: DeclSyntax(
                  InitializerDeclSyntax(
                    modifiers: DeclModifierListSyntax([
                      DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(8)]))
                    ]),
                    initKeyword: .keyword(.`init`),
                    signature: FunctionSignatureSyntax(
                      parameterClause: FunctionParameterClauseSyntax(
                        leftParen: .leftParenToken(),
                        parameters: FunctionParameterListSyntax([
                          FunctionParameterSyntax(
                            firstName: .identifier("accept"),
                            colon: .colonToken(),
                            type: TypeSyntax(
                              ArrayTypeSyntax(
                                leftSquare: .leftSquareToken(),
                                element: TypeSyntax(
                                  MemberTypeSyntax(
                                    baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime"))),
                                    period: .periodToken(),
                                    name: .identifier("AcceptHeaderContentType"),
                                    genericArgumentClause: GenericArgumentClauseSyntax(
                                      leftAngle: .leftAngleToken(),
                                      arguments: GenericArgumentListSyntax([
                                        GenericArgumentSyntax.create(argument: IdentifierTypeSyntax(name: .identifier("AcceptableContentType")))
                                      ]),
                                      rightAngle: .rightAngleToken()
                                    )
                                  )),
                                rightSquare: .rightSquareToken()
                              )),
                            defaultValue: InitializerClauseSyntax(
                              equal: .equalToken(),
                              value: FunctionCallExprSyntax(
                                callee: MemberAccessExprSyntax(
                                  period: .periodToken(),
                                  declName: DeclReferenceExprSyntax(baseName: .identifier("defaultValues"))
                                ))
                            )
                          )
                        ]),
                        rightParen: .rightParenToken()
                      )),
                    body: CodeBlockSyntax(
                      leftBrace: .leftBraceToken(),
                      statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(
                          item: CodeBlockItemSyntax.Item(
                            SequenceExprSyntax(
                              elements: ExprListSyntax([
                                ExprSyntax(
                                  MemberAccessExprSyntax(
                                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(12)]))),
                                    period: .periodToken(),
                                    declName: DeclReferenceExprSyntax(baseName: .identifier("accept"))
                                  )),
                                ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                                ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("accept"))),
                              ]))))
                      ]),
                      rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)])
                    )
                  ))),
            ]),
            rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
          )
        )
        VariableDeclSyntax(
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(4)]))
          ]),
          bindingSpecifier: .keyword(.var),
          bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("headers"))),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: TypeSyntax(
                  MemberTypeSyntax(
                    baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Input"))),
                    period: .periodToken(),
                    name: .identifier("Headers")
                  ))
              )
            )
          ])
        )
        InitializerDeclSyntax(
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(4)]))
          ]),
          initKeyword: .keyword(.`init`),
          signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
              leftParen: .leftParenToken(),
              parameters: FunctionParameterListSyntax([
                FunctionParameterSyntax(
                  leadingTrivia: [.newlines(1)],
                  firstName: .identifier("query"),
                  colon: .colonToken(),
                  type: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Input"))),
                      period: .periodToken(),
                      name: .identifier("Query")
                    )),
                  trailingComma: .commaToken()
                ),
                FunctionParameterSyntax(
                  firstName: .identifier("headers", leadingTrivia: [.newlines(1), .spaces(8)]),
                  colon: .colonToken(),
                  type: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Input"))),
                      period: .periodToken(),
                      name: .identifier("Headers")
                    )),
                  defaultValue: InitializerClauseSyntax(
                    equal: .equalToken(),
                    value: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
                      ))
                  )
                ),
              ]),
              rightParen: .rightParenToken(leadingTrivia: [.newlines(1), .spaces(4)])
            )),
          body: CodeBlockSyntax(
            leftBrace: .leftBraceToken(),
            statements: CodeBlockItemListSyntax([
              CodeBlockItemSyntax(
                item: CodeBlockItemSyntax.Item(
                  SequenceExprSyntax(
                    elements: ExprListSyntax([
                      ExprSyntax(
                        MemberAccessExprSyntax(
                          base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(8)]))),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("query"))
                        )),
                      ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                      ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("query"))),
                    ])))),
              CodeBlockItemSyntax(
                item: CodeBlockItemSyntax.Item(
                  SequenceExprSyntax(
                    elements: ExprListSyntax([
                      ExprSyntax(
                        MemberAccessExprSyntax(
                          base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(8)]))),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("headers"))
                        )),
                      ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                      ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("headers"))),
                    ])))),
            ]),
            rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
          )
        )
      }
    }
  }

  private func genQueryOutput(ts: TypeSchema, name: String, type: String, prefix: String, defMap: ExtDefMap) -> EnumDeclSyntax {
    let prefix = Lex.structNameFor(prefix: ts.prefix)
    return EnumDeclSyntax(
      attributes: [
        AttributeListSyntax.Element(
          AttributeSyntax(
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier("frozen"))
          ))
      ],
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .identifier("Output"),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"]),
    ) {
      StructDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        modifiers: [DeclModifierSyntax(name: .keyword(.public))],
        name: .identifier("Ok"),
        inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"])
      ) {
        EnumDeclSyntax(
          leadingTrivia: [.newlines(1), .spaces(14)],
          attributes: AttributeListSyntax {
            AttributeSyntax(
              atSign: .atSignToken(),
              attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("frozen")))
            )
          },
          modifiers: [DeclModifierSyntax(name: .keyword(.public))],
          name: .identifier("Body"),
          inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"])
        ) {
          genQueryOutputBody(ts: ts, name: name, type: type, prefix: prefix, defMap: defMap)
          VariableDeclSyntax(
            leadingTrivia: [.newlines(1), .spaces(18)],
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("json")),
                typeAnnotation: TypeAnnotationSyntax(
                  colon: .colonToken(),
                  type: IdentifierTypeSyntax(name: .identifier("ResponseBody"))
                ),
                accessorBlock: AccessorBlockSyntax(
                  leftBrace: .leftBraceToken(),
                  accessors: AccessorBlockSyntax.Accessors(
                    AccessorDeclListSyntax([
                      AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.get, leadingTrivia: [.newlines(1), .spaces(22)]),
                        effectSpecifiers: AccessorEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
                      ) {
                        SwitchExprSyntax(
                          leadingTrivia: [.newlines(1), .spaces(26)],
                          subject: DeclReferenceExprSyntax(baseName: .keyword(.self))
                        ) {
                          SwitchCaseSyntax(
                            label: SwitchCaseSyntax.Label(
                              SwitchCaseLabelSyntax(
                                leadingTrivia: [.newlines(1), .spaces(26)],
                                caseItems: SwitchCaseItemListSyntax([
                                  SwitchCaseItemSyntax(
                                    pattern: ValueBindingPatternSyntax(
                                      bindingSpecifier: .keyword(.let),
                                      pattern: ExpressionPatternSyntax(
                                        expression: FunctionCallExprSyntax(
                                          callee: MemberAccessExprSyntax(
                                            period: .periodToken(),
                                            declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                                          )
                                        ) {
                                          LabeledExprSyntax(expression: PatternExprSyntax(pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("body")))))
                                        }
                                      )
                                    ))
                                ]),
                                colon: .colonToken()
                              ))
                          ) {
                            CodeBlockItemSyntax(
                              item: CodeBlockItemSyntax.Item(
                                ReturnStmtSyntax(
                                  leadingTrivia: [.newlines(1), .spaces(30)],
                                  expression: DeclReferenceExprSyntax(baseName: .identifier("body"))
                                )))
                          }
                        }
                        .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(26)]))
                      }
                    ])),
                  rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(18)])
                )
              )
            ])
          )
        }
        VariableDeclSyntax(
          modifiers: [
            DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(14)]))
          ],
          bindingSpecifier: .keyword(.var),
          bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("body"))),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: TypeSyntax(
                  MemberTypeSyntax(
                    baseType: TypeSyntax(
                      MemberTypeSyntax(
                        baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Output"))),
                        period: .periodToken(),
                        name: .identifier("Ok")
                      )),
                    period: .periodToken(),
                    name: .identifier("Body")
                  ))
              )
            )
          ])
        )
        InitializerDeclSyntax(
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(14)]))
          ]),
          initKeyword: .keyword(.`init`),
          signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
              leftParen: .leftParenToken(),
              parameters: FunctionParameterListSyntax([
                FunctionParameterSyntax(
                  firstName: .identifier("body"),
                  colon: .colonToken(),
                  type: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(
                        MemberTypeSyntax(
                          baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Output"))),
                          period: .periodToken(),
                          name: .identifier("Ok")
                        )),
                      period: .periodToken(),
                      name: .identifier("Body")
                    ))
                )
              ]),
              rightParen: .rightParenToken()
            ))
        ) {
          SequenceExprSyntax(
            elements: ExprListSyntax([
              ExprSyntax(
                MemberAccessExprSyntax(
                  base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(18)]))),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier("body"))
                )),
              ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
              ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("body"))),
            ]))
        }
      }
      EnumCaseDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        elements: EnumCaseElementListSyntax([
          EnumCaseElementSyntax(
            name: .identifier("ok"),
            parameterClause: EnumCaseParameterClauseSyntax(
              leftParen: .leftParenToken(),
              parameters: EnumCaseParameterListSyntax([
                EnumCaseParameterSyntax(
                  type: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Output"))),
                      period: .periodToken(),
                      name: .identifier("Ok")
                    ))
                )
              ]),
              rightParen: .rightParenToken()
            )
          )
        ])
      )
      VariableDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        modifiers: DeclModifierListSyntax([
          DeclModifierSyntax(name: .keyword(.public))
        ]),
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("ok"))),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: TypeSyntax(
                MemberTypeSyntax(
                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Output"))),
                  period: .periodToken(),
                  name: .identifier("Ok")
                ))
            ),
            accessorBlock: AccessorBlockSyntax(
              leftBrace: .leftBraceToken(),
              accessors: AccessorBlockSyntax.Accessors(
                AccessorDeclListSyntax([
                  AccessorDeclSyntax(
                    accessorSpecifier: .keyword(.get, leadingTrivia: [.newlines(1), .spaces(14)]),
                    effectSpecifiers: AccessorEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
                  ) {
                    ExpressionStmtSyntax(
                      expression: ExprSyntax(
                        SwitchExprSyntax(
                          leadingTrivia: [.newlines(1), .spaces(18)],
                          subject: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                        ) {
                          SwitchCaseSyntax(
                            label: SwitchCaseSyntax.Label(
                              SwitchCaseLabelSyntax(
                                leadingTrivia: [.newlines(1), .spaces(18)],
                                caseItems: SwitchCaseItemListSyntax([
                                  SwitchCaseItemSyntax(
                                    pattern: ValueBindingPatternSyntax(
                                      bindingSpecifier: .keyword(.let),
                                      pattern: ExpressionPatternSyntax(
                                        expression: FunctionCallExprSyntax(
                                          callee: MemberAccessExprSyntax(
                                            period: .periodToken(),
                                            declName: DeclReferenceExprSyntax(baseName: .identifier("ok"))
                                          )
                                        ) {
                                          LabeledExprSyntax(expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("response"))))
                                        }
                                      )
                                    ))
                                ]),
                                colon: .colonToken()
                              ))
                          ) {
                            ReturnStmtSyntax(
                              leadingTrivia: [.newlines(1), .spaces(22)],
                              expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("response")))
                            )
                          }
                          SwitchCaseSyntax(
                            label: SwitchCaseSyntax.Label(
                              SwitchDefaultLabelSyntax(
                                leadingTrivia: [.newlines(1), .spaces(18)],
                                colon: .colonToken()
                              ))
                          ) {
                            TryExprSyntax(
                              leadingTrivia: [.newlines(1), .spaces(22)],
                              expression: FunctionCallExprSyntax(
                                callee: DeclReferenceExprSyntax(baseName: .identifier("throwUnexpectedResponseStatus"))
                              ) {
                                LabeledExprSyntax(
                                  label: .identifier("expectedStatus", leadingTrivia: [.newlines(1), .spaces(26)]),
                                  colon: .colonToken(),
                                  expression: StringLiteralExprSyntax(content: "ok"),
                                )
                                LabeledExprSyntax(
                                  label: .identifier("response", leadingTrivia: [.newlines(1), .spaces(26)]),
                                  colon: .colonToken(),
                                  expression: DeclReferenceExprSyntax(baseName: .keyword(.self))
                                )
                              }
                              .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(22)]))
                            )
                          }
                        }
                        .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(18)]))
                      ))
                  }
                  .with(\.body!.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(14)]))
                ])),
              rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(10)])
            )
          )
        ])
      )
      EnumCaseDeclSyntax(
        leadingTrivia: [.newlines(1), .spaces(10)],
        elements: EnumCaseElementListSyntax([
          EnumCaseElementSyntax(
            name: .identifier("undocumented"),
            parameterClause: EnumCaseParameterClauseSyntax(
              leftParen: .leftParenToken(),
              parameters: EnumCaseParameterListSyntax([
                EnumCaseParameterSyntax(
                  firstName: .identifier("statusCode"),
                  colon: .colonToken(),
                  type: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Swift"))),
                      period: .periodToken(),
                      name: .identifier("Int")
                    )),
                  trailingComma: .commaToken()
                ),
                EnumCaseParameterSyntax(
                  type: TypeSyntax(
                    MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime"))),
                      period: .periodToken(),
                      name: .identifier("UndocumentedPayload")
                    ))
                ),
              ]),
              rightParen: .rightParenToken()
            )
          )
        ])
      )
    }
  }

  private func genQueryOutputBody(ts: TypeSchema, name: String, type: String, prefix: String, defMap: ExtDefMap) -> EnumCaseDeclSyntax {
    EnumCaseDeclSyntax(
      leadingTrivia: [.newlines(1), .spaces(18)],
      elements: EnumCaseElementListSyntax([
        EnumCaseElementSyntax(
          name: .identifier("json"),
          parameterClause: EnumCaseParameterClauseSyntax(
            leftParen: .leftParenToken(),
            parameters: EnumCaseParameterListSyntax([
              EnumCaseParameterSyntax(
                type: IdentifierTypeSyntax(name: .identifier("ResponseBody"))
              )
            ]),
            rightParen: .rightParenToken()
          )
        )
      ])
    )
  }

  private func genAcceptableContentType() -> EnumDeclSyntax {
    EnumDeclSyntax(
      attributes: AttributeListSyntax {
        AttributeSyntax(
          atSign: .atSignToken(),
          attributeName: IdentifierTypeSyntax(name: .identifier("frozen"))
        )
      },
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .identifier("AcceptableContentType"),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ["AcceptableProtocol"])
    ) {
      EnumCaseDeclSyntax(
        elements: EnumCaseElementListSyntax([
          EnumCaseElementSyntax(name: .identifier("json"))
        ])
      )
      EnumCaseDeclSyntax(
        elements: [
          EnumCaseElementSyntax(
            name: .identifier("other"),
            parameterClause: EnumCaseParameterClauseSyntax(
              leftParen: .leftParenToken(),
              parameters: EnumCaseParameterListSyntax([
                EnumCaseParameterSyntax(
                  type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
                )
              ]),
              rightParen: .rightParenToken()
            )
          )
        ]
      )
      MemberBlockItemSyntax(
        decl: DeclSyntax(
          InitializerDeclSyntax(
            leadingTrivia: [.newlines(1)],
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            optionalMark: .postfixQuestionMarkToken(),
            signature: FunctionSignatureSyntax(
              parameterClause: FunctionParameterClauseSyntax(
                leftParen: .leftParenToken(),
                parameters: [
                  FunctionParameterSyntax(
                    firstName: .identifier("rawValue"),
                    colon: .colonToken(),
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
                  )
                ],
                rightParen: .rightParenToken()
              )),
          ) {
            CodeBlockItemSyntax(
              item: CodeBlockItemSyntax.Item(
                ExpressionStmtSyntax(
                  expression: ExprSyntax(
                    SwitchExprSyntax(
                      leadingTrivia: [.newlines(1), .spaces(8)],
                      subject: FunctionCallExprSyntax(
                        callee: MemberAccessExprSyntax(
                          base: DeclReferenceExprSyntax(baseName: .identifier("rawValue")),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("lowercased"))
                        )
                      )
                    ) {
                      SwitchCaseSyntax(
                        label: SwitchCaseSyntax.Label(
                          SwitchCaseLabelSyntax(
                            leadingTrivia: [.newlines(1), .spaces(8)],
                            caseItems: SwitchCaseItemListSyntax([
                              SwitchCaseItemSyntax(
                                pattern: PatternSyntax(
                                  ExpressionPatternSyntax(
                                    expression: ExprSyntax(
                                      StringLiteralExprSyntax(
                                        openingQuote: .stringQuoteToken(),
                                        segments: StringLiteralSegmentListSyntax([
                                          StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("application/json")))
                                        ]),
                                        closingQuote: .stringQuoteToken()
                                      )))))
                            ]),
                            colon: .colonToken()
                          )),
                        statements: CodeBlockItemListSyntax([
                          CodeBlockItemSyntax(
                            item: CodeBlockItemSyntax.Item(
                              SequenceExprSyntax(
                                elements: ExprListSyntax([
                                  ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(12)]))),
                                  ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                                  ExprSyntax(
                                    MemberAccessExprSyntax(
                                      period: .periodToken(),
                                      declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                                    )),
                                ]))))
                        ])
                      )
                      SwitchCaseSyntax(
                        label: SwitchCaseSyntax.Label(
                          SwitchDefaultLabelSyntax(
                            leadingTrivia: [.newlines(1)],
                            colon: .colonToken()
                          ))
                      ) {
                        SequenceExprSyntax {
                          ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(12)])))
                          ExprSyntax(AssignmentExprSyntax(equal: .equalToken()))
                          ExprSyntax(
                            FunctionCallExprSyntax(
                              callee: MemberAccessExprSyntax(
                                period: .periodToken(),
                                declName: DeclReferenceExprSyntax(baseName: .identifier("other"))
                              )
                            ) {
                              LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue"))))
                            })
                        }
                      }
                    }
                    .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1)]))
                  ))))
          }
        ))
      MemberBlockItemSyntax(
        decl: DeclSyntax(
          VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
              DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(4)]))
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
                  leftBrace: .leftBraceToken(),
                  accessors: AccessorBlockSyntax.Accessors(
                    CodeBlockItemListSyntax([
                      CodeBlockItemSyntax(
                        item: CodeBlockItemSyntax.Item(
                          ExpressionStmtSyntax(
                            expression: ExprSyntax(
                              SwitchExprSyntax(
                                leadingTrivia: [.newlines(1), .spaces(8)],
                                subject: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                              ) {
                                SwitchCaseSyntax(
                                  label: SwitchCaseSyntax.Label(
                                    SwitchCaseLabelSyntax(
                                      leadingTrivia: [.newlines(1), .spaces(8)]) {
                                        SwitchCaseItemSyntax(
                                          pattern: PatternSyntax(
                                            ValueBindingPatternSyntax(
                                              bindingSpecifier: .keyword(.let),
                                              pattern: PatternSyntax(
                                                ExpressionPatternSyntax(
                                                  expression: FunctionCallExprSyntax(
                                                    callee: MemberAccessExprSyntax(
                                                      period: .periodToken(),
                                                      declName: DeclReferenceExprSyntax(baseName: .identifier("other"))
                                                    )
                                                  ) {
                                                    LabeledExprSyntax(expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("string"))))
                                                  }
                                                )
                                              )
                                            )))
                                      },
                                  )
                                ) {
                                  ReturnStmtSyntax(
                                    leadingTrivia: [.newlines(1), .spaces(12)],
                                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("string")))
                                  )
                                }
                                SwitchCaseSyntax(
                                  label: SwitchCaseSyntax.Label(
                                    SwitchCaseLabelSyntax(
                                      leadingTrivia: [.newlines(1), .spaces(8)],
                                      caseItems: SwitchCaseItemListSyntax([
                                        SwitchCaseItemSyntax(
                                          pattern: PatternSyntax(
                                            ExpressionPatternSyntax(
                                              expression: ExprSyntax(
                                                MemberAccessExprSyntax(
                                                  period: .periodToken(),
                                                  declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                                                )))))
                                      ]),
                                      colon: .colonToken()
                                    ))
                                ) {
                                  ReturnStmtSyntax(
                                    leadingTrivia: [.newlines(1), .spaces(12)],
                                    expression: ExprSyntax(
                                      StringLiteralExprSyntax(
                                        openingQuote: .stringQuoteToken(),
                                        segments: StringLiteralSegmentListSyntax([
                                          StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("application/json")))
                                        ]),
                                        closingQuote: .stringQuoteToken()
                                      ))
                                  )
                                }
                              }
                              .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)]))
                            ))))
                    ])),
                  rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                )
              )
            ])
          )))
      MemberBlockItemSyntax(
        decl: DeclSyntax(
          VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
              DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(4)])),
              DeclModifierSyntax(name: .keyword(.static)),
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
              PatternBindingSyntax(
                pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("allCases"))),
                typeAnnotation: TypeAnnotationSyntax(
                  colon: .colonToken(),
                  type: TypeSyntax(
                    ArrayTypeSyntax(
                      leftSquare: .leftSquareToken(),
                      element: TypeSyntax(IdentifierTypeSyntax(name: .keyword(.Self))),
                      rightSquare: .rightSquareToken()
                    ))
                ),
                accessorBlock: AccessorBlockSyntax(
                  leftBrace: .leftBraceToken(),
                  accessors: AccessorBlockSyntax.Accessors(
                    CodeBlockItemListSyntax([
                      CodeBlockItemSyntax(
                        item: CodeBlockItemSyntax.Item(
                          ArrayExprSyntax(leadingTrivia: [.newlines(1), .spaces(8)], rightSquare: .rightSquareToken(leadingTrivia: [.newlines(1), .spaces(8)])) {
                            ArrayElementSyntax(
                              expression: MemberAccessExprSyntax(
                                period: .periodToken(leadingTrivia: [.newlines(1), .spaces(12)]),
                                declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                              ))
                          }
                        )
                      )
                    ])),
                  rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                )
              )
            ])
          )))
    }
  }
}
