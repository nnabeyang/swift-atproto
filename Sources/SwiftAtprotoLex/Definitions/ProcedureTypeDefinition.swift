import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct ProcedureTypeDefinition: HTTPAPITypeDefinition, SwiftCodeGeneratable {
  var type: FieldType { .procedure }
  let output: OutputType?
  var input: InputType?
  let description: String?
  let errors: [ErrorResponse]?

  private enum CodingKeys: String, CodingKey {
    case type
    case output
    case input
    case description
    case errors
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    output = try container.decodeIfPresent(OutputType.self, forKey: .output, configuration: configuration)
    input = try container.decodeIfPresent(InputType.self, forKey: .input, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    errors = try container.decodeIfPresent([ErrorResponse].self, forKey: .errors)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(output, forKey: .output)
    try container.encodeIfPresent(input, forKey: .input)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(errors, forKey: .errors)
  }

  var contentType: String {
    if let input {
      switch input.encoding {
      case .json, .jsonl, .text, .mp4:
        return input.encoding.rawValue
      case .cbor, .any, .car:
        return "*/*"
      }
    }
    return "*/*"
  }

  func inputBody(fname: String, defMap: ExtDefMap, prefix: String) -> EnumCaseElementSyntax? {
    if let input {
      switch input.encoding {
      case .json, .jsonl:
        let token: String = {
          guard let schema = input.schema else {
            return "EmptyResponse"
          }
          let outname: String
          if case .ref(let def) = schema.type {
            (_, outname) = schema.namesFromRef(ref: def.ref, defMap: defMap)
          } else {
            outname = "\(fname)_Input"
          }
          return outname
        }()
        return EnumCaseElementSyntax(
          name: .identifier("json"),
          parameterClause: EnumCaseParameterClauseSyntax(
            leftParen: .leftParenToken(),
            parameters: EnumCaseParameterListSyntax([
              EnumCaseParameterSyntax(
                type: IdentifierTypeSyntax(name: .identifier(token))
              )
            ]),
            rightParen: .rightParenToken()
          )
        )
      case .text:
        return EnumCaseElementSyntax(
          name: .identifier("json"),
          parameterClause: EnumCaseParameterClauseSyntax(
            leftParen: .leftParenToken(),
            parameters: EnumCaseParameterListSyntax([
              EnumCaseParameterSyntax(
                type: IdentifierTypeSyntax(name: .identifier("String"))
              )
            ]),
            rightParen: .rightParenToken()
          )
        )
      case .cbor, .car, .any, .mp4:
        return EnumCaseElementSyntax(
          name: .identifier("binary"),
          parameterClause: EnumCaseParameterClauseSyntax(
            leftParen: .leftParenToken(),
            parameters: EnumCaseParameterListSyntax([
              EnumCaseParameterSyntax(
                type: IdentifierTypeSyntax(name: .identifier("HTTPBody"))
              )
            ]),
            rightParen: .rightParenToken()
          )
        )
      }
    }
    return nil
  }

  func requestBody(fname: String, defMap: ExtDefMap, prefix: String) -> IdentifierTypeSyntax {
    if let input {
      switch input.encoding {
      case .json, .jsonl:
        let token: String = {
          guard let schema = input.schema else {
            return "EmptyResponse"
          }
          let outname: String
          if case .ref(let def) = schema.type {
            (_, outname) = schema.namesFromRef(ref: def.ref, defMap: defMap)
          } else {
            outname = "\(fname)_Input"
          }
          return outname
        }()
        return IdentifierTypeSyntax(name: .identifier(token))
      case .text:
        return IdentifierTypeSyntax(name: .identifier("String"))
      case .cbor, .car, .any, .mp4:
        return IdentifierTypeSyntax(name: .identifier("Data"))
      }
    }
    return IdentifierTypeSyntax(name: .identifier("Bool"))
  }

  func responseBody(fname: String, defMap: ExtDefMap, prefix: String) -> IdentifierTypeSyntax {
    if let output {
      switch output.encoding {
      case .json, .jsonl:
        let token: String = {
          guard let schema = output.schema else {
            return "EmptyResponse"
          }
          let outname: String
          if case .ref(let def) = schema.type {
            (_, outname) = schema.namesFromRef(ref: def.ref, defMap: defMap)
          } else {
            outname = "\(fname)_Output"
          }
          return outname
        }()
        return IdentifierTypeSyntax(name: .identifier(token))
      case .text:
        return IdentifierTypeSyntax(name: .identifier("String"))
      case .cbor, .car, .any, .mp4:
        return IdentifierTypeSyntax(name: .identifier("Data"))
      }
    }
    return IdentifierTypeSyntax(name: .identifier("EmptyResponse"))
  }

  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [FunctionParameterSyntax] {
    var arguments = [FunctionParameterSyntax]()
    guard let input else { return arguments }
    switch input.encoding {
    case .cbor, .any, .car, .mp4:
      let tname = "Data"
      arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname)))
    case .text:
      let tname = "String"
      arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname)))
    case .json, .jsonl:
      let tname: String
      if case .ref(let ref) = input.schema?.type {
        (_, tname) = ts.namesFromRef(ref: ref.ref, defMap: defMap)
      } else {
        tname = "\(fname)_Input"
      }
      arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: "\(prefix).\(tname)")))
    }
    return arguments
  }

  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol {
    NilLiteralExprSyntax()
  }

  func inputType(fname: String, defMap: ExtDefMap, prefix: String, binaryTypeName: String = "Data") -> ExprSyntax {
    guard let token = input?.typeName(fname: fname, prefix: prefix, defMap: defMap, binaryTypeName: binaryTypeName, isOutput: false) else {
      return ExprSyntax(
        OptionalChainingExprSyntax(
          expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("Bool"))),
          questionMark: .postfixQuestionMarkToken()
        ))
    }
    return ExprSyntax(DeclReferenceExprSyntax(baseName: token))
  }

  var isBinary: Bool {
    input?.isBinary ?? false
  }

  func generateDeclaration(leadingTrivia: SwiftSyntax.Trivia?, ts: TypeSchema, name: String, type: String, defMap: ExtDefMap, generate: GenerateOption) -> any DeclSyntaxProtocol {
    let prefix = Lex.structNameFor(prefix: ts.prefix)
    let responseBody = responseBody(fname: name, defMap: defMap, prefix: Lex.structNameFor(prefix: ts.prefix))
    return EnumDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier(ts.typeName),
      inheritanceClause: InheritanceClauseSyntax {
        InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("XRPCProcedure")))
      }
    ) {
      staticLetDecl(leadingTrivia: [.newlines(1), .spaces(2)], ident: "id", value: StringLiteralExprSyntax(content: type))
      staticLetDecl(leadingTrivia: [.newlines(1), .spaces(2)], ident: "contentType", value: StringLiteralExprSyntax(content: contentType))
      TypeAliasDeclSyntax(
        modifiers: [DeclModifierSyntax(name: .keyword(.public, leadingTrivia: .newline))],
        name: .identifier("RequestBody"),
        initializer: TypeInitializerClauseSyntax(
          equal: .equalToken(),
          value: requestBody(fname: name, defMap: defMap, prefix: Lex.structNameFor(prefix: ts.prefix))
        )
      )
      TypeAliasDeclSyntax(
        modifiers: [DeclModifierSyntax(name: .keyword(.public, leadingTrivia: .newline))],
        name: .identifier("ResponseBody"),
        initializer: TypeInitializerClauseSyntax(
          equal: .equalToken(),
          value: responseBody
        )
      )
      if generate.contains(.server) {
        MemberBlockItemSyntax(
          decl: DeclSyntax(
            StructDeclSyntax(
              leadingTrivia: [.newlines(1), .spaces(2)],
              modifiers: [DeclModifierSyntax(name: .keyword(.public))],
              name: .identifier("Input"),
              inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"])
            ) {
              StructDeclSyntax(
                leadingTrivia: [.newlines(1), .spaces(4)],
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                name: .identifier("Headers"),
                inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"])
              ) {
                VariableDeclSyntax(
                  leadingTrivia: [.newlines(1), .spaces(6)],
                  modifiers: [DeclModifierSyntax(name: .keyword(.public))],
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
                                    GenericArgumentSyntax.create(
                                      argument: MemberTypeSyntax(
                                        baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(ts.typeName))),
                                        period: .periodToken(),
                                        name: .identifier("AcceptableContentType")
                                      ))
                                  ]),
                                  rightAngle: .rightAngleToken()
                                )
                              )),
                            rightSquare: .rightSquareToken()
                          ))
                      )
                    )
                  ])
                )
                InitializerDeclSyntax(
                  leadingTrivia: [.newlines(1), .spaces(6)],
                  modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public))
                  ]),
                  signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax(
                      leftParen: .leftParenToken(),
                      parameters: FunctionParameterListSyntax([
                        FunctionParameterSyntax(
                          firstName: .identifier("accept"),
                          colon: .colonToken(),
                          type: ArrayTypeSyntax(
                            leftSquare: .leftSquareToken(),
                            element: MemberTypeSyntax(
                              baseType: IdentifierTypeSyntax(name: .identifier("OpenAPIRuntime")),
                              period: .periodToken(),
                              name: .identifier("AcceptHeaderContentType"),
                              genericArgumentClause: GenericArgumentClauseSyntax {
                                GenericArgumentSyntax.create(
                                  argument: MemberTypeSyntax(
                                    baseType: IdentifierTypeSyntax(name: .identifier(ts.typeName)),
                                    period: .periodToken(),
                                    name: .identifier("AcceptableContentType")
                                  )
                                )
                              }
                            ),
                            rightSquare: .rightSquareToken()
                          ),
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
                    ))
                ) {
                  SequenceExprSyntax(leadingTrivia: [.newlines(1), .spaces(8)]) {
                    MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .identifier("accept"))
                    )
                    AssignmentExprSyntax(equal: .equalToken())
                    DeclReferenceExprSyntax(baseName: .identifier("accept"))
                  }
                }
              }
              VariableDeclSyntax(
                leadingTrivia: [.newlines(1), .spaces(4)],
                modifiers: [
                  DeclModifierSyntax(name: .keyword(.public))
                ],
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                  PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("headers")),
                    typeAnnotation: TypeAnnotationSyntax(
                      colon: .colonToken(),
                      type: TypeSyntax(
                        MemberTypeSyntax(
                          baseType: TypeSyntax(
                            MemberTypeSyntax(
                              baseType: IdentifierTypeSyntax(name: .identifier(ts.typeName)),
                              period: .periodToken(),
                              name: .identifier("Input")
                            )),
                          period: .periodToken(),
                          name: .identifier("Headers")
                        ))
                    )
                  )
                ])
              )
              if let input = inputBody(fname: name, defMap: defMap, prefix: prefix) {
                EnumDeclSyntax(
                  leadingTrivia: [.newlines(2), .spaces(4)],
                  attributes: AttributeListSyntax {
                    AttributeSyntax(
                      atSign: .atSignToken(),
                      attributeName: IdentifierTypeSyntax(name: .identifier("frozen"))
                    )
                  },
                  modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                  name: .identifier("Body"),
                  inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"])
                ) {
                  EnumCaseDeclSyntax(leadingTrivia: [.newlines(1), .spaces(6)]) {
                    input
                  }
                }
                varDecl(
                  ident: "body",
                  type: MemberTypeSyntax(
                    baseType: MemberTypeSyntax(
                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(ts.typeName))),
                      name: .identifier("Input")
                    ),
                    name: .identifier("Body")
                  ))
              }
              procedureInputInitializer(leadingTrivia: [.newlines(2), .spaces(4)], typeName: ts.typeName)
            }
          ))
        MemberBlockItemSyntax(
          decl: DeclSyntax(
            EnumDeclSyntax(
              attributes: AttributeListSyntax {
                AttributeSyntax(
                  atSign: .atSignToken(leadingTrivia: [.newlines(1), .spaces(2)]),
                  attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("frozen")))
                )
              },
              modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
              ]),
              enumKeyword: .keyword(.enum),
              name: .identifier("Output"),
              inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"]),
              memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: MemberBlockItemListSyntax([
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      StructDeclSyntax(
                        leadingTrivia: [.newlines(1), .spaces(4)],
                        modifiers: [
                          DeclModifierSyntax(name: .keyword(.public))
                        ],
                        name: .identifier("Ok"),
                        inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"])
                      ) {
                        MemberBlockItemSyntax(
                          decl: DeclSyntax(
                            EnumDeclSyntax(
                              attributes: AttributeListSyntax {
                                AttributeSyntax(
                                  atSign: .atSignToken(leadingTrivia: [.newlines(1), .spaces(6)]),
                                  attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("frozen")))
                                )
                              },
                              modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                              name: .identifier("Body"),
                              inheritanceClause: InheritanceClauseSyntax(typeNames: ["Sendable", "Hashable"]),
                              memberBlock: MemberBlockSyntax(
                                leftBrace: .leftBraceToken(),
                                members: MemberBlockItemListSyntax([
                                  MemberBlockItemSyntax(
                                    decl: DeclSyntax(
                                      EnumCaseDeclSyntax(
                                        leadingTrivia: [.newlines(1), .spaces(8)],
                                        elements: EnumCaseElementListSyntax([
                                          EnumCaseElementSyntax(
                                            name: .identifier("json"),
                                            parameterClause: EnumCaseParameterClauseSyntax(
                                              leftParen: .leftParenToken(),
                                              parameters: EnumCaseParameterListSyntax([
                                                EnumCaseParameterSyntax(
                                                  type: TypeSyntax(responseBody)
                                                )
                                              ]),
                                              rightParen: .rightParenToken()
                                            )
                                          )
                                        ])
                                      ))),
                                  MemberBlockItemSyntax(
                                    decl: DeclSyntax(
                                      VariableDeclSyntax(
                                        modifiers: DeclModifierListSyntax([
                                          DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(8)]))
                                        ]),
                                        bindingSpecifier: .keyword(.var),
                                        bindings: PatternBindingListSyntax([
                                          PatternBindingSyntax(
                                            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("json"))),
                                            typeAnnotation: TypeAnnotationSyntax(
                                              colon: .colonToken(),
                                              type: TypeSyntax(responseBody)
                                            ),
                                            accessorBlock: AccessorBlockSyntax(
                                              leftBrace: .leftBraceToken(),
                                              accessors: .accessors(
                                                AccessorDeclListSyntax([
                                                  AccessorDeclSyntax(
                                                    accessorSpecifier: .keyword(.get, leadingTrivia: [.newlines(1), .spaces(10)]),
                                                    effectSpecifiers: AccessorEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))),
                                                    body: CodeBlockSyntax(
                                                      leftBrace: .leftBraceToken(),
                                                      statements: CodeBlockItemListSyntax([
                                                        CodeBlockItemSyntax(
                                                          item: CodeBlockItemSyntax.Item(
                                                            ExpressionStmtSyntax(
                                                              expression: ExprSyntax(
                                                                SwitchExprSyntax(
                                                                  leadingTrivia: [.newlines(1), .spaces(12)],
                                                                  subject: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                                                                ) {
                                                                  SwitchCaseSyntax(
                                                                    label: SwitchCaseSyntax.Label(
                                                                      SwitchCaseLabelSyntax(
                                                                        leadingTrivia: [.newlines(1), .spaces(12)],
                                                                        caseItems: SwitchCaseItemListSyntax([
                                                                          SwitchCaseItemSyntax(
                                                                            pattern: PatternSyntax(
                                                                              ExpressionPatternSyntax(
                                                                                expression: ExprSyntax(
                                                                                  FunctionCallExprSyntax(
                                                                                    callee: MemberAccessExprSyntax(
                                                                                      period: .periodToken(),
                                                                                      declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                                                                                    )
                                                                                  ) {
                                                                                    LabeledExprSyntax(
                                                                                      expression: PatternExprSyntax(
                                                                                        pattern: ValueBindingPatternSyntax(
                                                                                          bindingSpecifier: .keyword(.let),
                                                                                          pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("body")))
                                                                                        )))
                                                                                  }
                                                                                ))))
                                                                        ]),
                                                                        colon: .colonToken()
                                                                      )),
                                                                    statements: CodeBlockItemListSyntax([
                                                                      CodeBlockItemSyntax(
                                                                        item: CodeBlockItemSyntax.Item(
                                                                          ReturnStmtSyntax(
                                                                            leadingTrivia: [.newlines(1), .spaces(14)],
                                                                            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("body")))
                                                                          )))
                                                                    ])
                                                                  )
                                                                }
                                                                .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(12)]))
                                                              ))))
                                                      ]),
                                                      rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(10)])
                                                    )
                                                  )
                                                ])),
                                              rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)])
                                            )
                                          )
                                        ])
                                      ))),
                                ]),
                                rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(6)])
                              )
                            )))
                        MemberBlockItemSyntax(
                          decl: DeclSyntax(
                            VariableDeclSyntax(
                              modifiers: DeclModifierListSyntax([
                                DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(2), .spaces(6)]))
                              ]),
                              bindingSpecifier: .keyword(.var),
                              bindings: PatternBindingListSyntax([
                                PatternBindingSyntax(
                                  pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("body"))),
                                  typeAnnotation: TypeAnnotationSyntax(
                                    colon: .colonToken(),
                                    type: TypeSyntax(
                                      MemberTypeSyntax(
                                        baseType:
                                          MemberTypeSyntax(
                                            baseType: TypeSyntax(
                                              MemberTypeSyntax(
                                                baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(ts.typeName))),
                                                period: .periodToken(),
                                                name: .identifier("Output")
                                              )),
                                            period: .periodToken(),
                                            name: .identifier("Ok")
                                          ),
                                        period: .periodToken(),
                                        name: .identifier("Body")
                                      ))
                                  )
                                )
                              ])
                            )))
                        MemberBlockItemSyntax(
                          decl: DeclSyntax(
                            InitializerDeclSyntax(
                              modifiers: DeclModifierListSyntax([
                                DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(2), .spaces(6)]))
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
                                              baseType: TypeSyntax(
                                                MemberTypeSyntax(
                                                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(ts.typeName))),
                                                  period: .periodToken(),
                                                  name: .identifier("Output")
                                                )),
                                              period: .periodToken(),
                                              name: .identifier("Ok")
                                            )),
                                          period: .periodToken(),
                                          name: .identifier("Body")
                                        ))
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
                                              base: DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(8)])),
                                              period: .periodToken(),
                                              declName: DeclReferenceExprSyntax(baseName: .identifier("body"))
                                            )),
                                          ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                                          ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("body"))),
                                        ]))))
                                ]),
                                rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(6)])
                              )
                            )))
                      }
                    )),
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      EnumCaseDeclSyntax(
                        leadingTrivia: [.newlines(2), .spaces(4)],
                        elements: EnumCaseElementListSyntax([
                          EnumCaseElementSyntax(
                            name: .identifier("ok"),
                            parameterClause: EnumCaseParameterClauseSyntax(
                              leftParen: .leftParenToken(),
                              parameters: EnumCaseParameterListSyntax([
                                EnumCaseParameterSyntax(
                                  type: TypeSyntax(
                                    MemberTypeSyntax(
                                      baseType: TypeSyntax(
                                        MemberTypeSyntax(
                                          baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(ts.typeName))),
                                          period: .periodToken(),
                                          name: .identifier("Output")
                                        )),
                                      period: .periodToken(),
                                      name: .identifier("Ok")
                                    ))
                                )
                              ]),
                              rightParen: .rightParenToken()
                            )
                          )
                        ])
                      ))),
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      VariableDeclSyntax(
                        modifiers: DeclModifierListSyntax([
                          DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(2), .spaces(4)]))
                        ]),
                        bindingSpecifier: .keyword(.var),
                        bindings: PatternBindingListSyntax([
                          PatternBindingSyntax(
                            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("ok"))),
                            typeAnnotation: TypeAnnotationSyntax(
                              colon: .colonToken(),
                              type: TypeSyntax(
                                MemberTypeSyntax(
                                  baseType: TypeSyntax(
                                    MemberTypeSyntax(
                                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(ts.typeName))),
                                      period: .periodToken(),
                                      name: .identifier("Output")
                                    )),
                                  period: .periodToken(),
                                  name: .identifier("Ok")
                                ))
                            ),
                            accessorBlock: AccessorBlockSyntax(
                              leftBrace: .leftBraceToken(),
                              accessors: AccessorBlockSyntax.Accessors(
                                AccessorDeclListSyntax([
                                  AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.get, leadingTrivia: [.newlines(1), .spaces(6)]),
                                    effectSpecifiers: AccessorEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))),
                                    body: CodeBlockSyntax(
                                      leftBrace: .leftBraceToken(),
                                      statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(
                                          item: CodeBlockItemSyntax.Item(
                                            ExpressionStmtSyntax(
                                              expression: ExprSyntax(
                                                SwitchExprSyntax(
                                                  leadingTrivia: [.newlines(1), .spaces(8)],
                                                  subject: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                                                ) {
                                                  SwitchCaseSyntax(
                                                    label: SwitchCaseSyntax.Label(
                                                      SwitchCaseLabelSyntax(
                                                        leadingTrivia: [.newlines(1), .spaces(8)]) {
                                                          SwitchCaseItemSyntax(
                                                            pattern: PatternSyntax(
                                                              ExpressionPatternSyntax(
                                                                expression: ExprSyntax(
                                                                  FunctionCallExprSyntax(
                                                                    callee: ExprSyntax(
                                                                      MemberAccessExprSyntax(
                                                                        period: .periodToken(),
                                                                        declName: DeclReferenceExprSyntax(baseName: .identifier("ok"))
                                                                      ))
                                                                  ) {
                                                                    LabeledExprSyntax(
                                                                      expression: ExprSyntax(
                                                                        PatternExprSyntax(
                                                                          pattern: PatternSyntax(
                                                                            ValueBindingPatternSyntax(
                                                                              bindingSpecifier: .keyword(.let),
                                                                              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("response")))
                                                                            )))))
                                                                  }
                                                                ))))
                                                        }
                                                    )
                                                  ) {
                                                    ReturnStmtSyntax(
                                                      leadingTrivia: [.newlines(1), .spaces(10)],
                                                      expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("response")))
                                                    )
                                                  }
                                                  SwitchCaseSyntax(
                                                    label: SwitchCaseSyntax.Label(
                                                      SwitchDefaultLabelSyntax(
                                                        leadingTrivia: [.newlines(1), .spaces(8)],
                                                        colon: .colonToken()
                                                      ))
                                                  ) {
                                                    TryExprSyntax(
                                                      leadingTrivia: [.newlines(1), .spaces(10)],
                                                      expression: FunctionCallExprSyntax(
                                                        callee: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("throwUnexpectedResponseStatus")))
                                                      ) {
                                                        LabeledExprSyntax(
                                                          label: .identifier("expectedStatus", leadingTrivia: [.newlines(1), .spaces(12)]),
                                                          colon: .colonToken(),
                                                          expression: ExprSyntax(
                                                            StringLiteralExprSyntax(
                                                              openingQuote: .stringQuoteToken(),
                                                              segments: StringLiteralSegmentListSyntax([
                                                                StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("ok")))
                                                              ]),
                                                              closingQuote: .stringQuoteToken()
                                                            )),
                                                          trailingComma: .commaToken()
                                                        )
                                                        LabeledExprSyntax(
                                                          label: .identifier("response", leadingTrivia: [.newlines(1), .spaces(12)]),
                                                          colon: .colonToken(),
                                                          expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                                                        )
                                                      }
                                                      .with(\.rightParen, .rightParenToken(leadingTrivia: [.newlines(1), .spaces(10)]))
                                                    )
                                                  }
                                                }
                                                .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(8)]))
                                              ))))
                                      ]),
                                      rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(6)])
                                    )
                                  )
                                ])),
                              rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                            )
                          )
                        ])
                      ))),
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      EnumCaseDeclSyntax(
                        leadingTrivia: [.newlines(1), .spaces(4)],
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
                      ))),
                ]),
                rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(2)])
              )
            )))
        MemberBlockItemSyntax(
          decl: DeclSyntax(
            EnumDeclSyntax(
              attributes: AttributeListSyntax {
                AttributeSyntax(
                  atSign: .atSignToken(leadingTrivia: [.newlines(1), .spaces(2)]),
                  attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("frozen")))
                )
              },
              modifiers: [DeclModifierSyntax(name: .keyword(.public))],
              name: .identifier("AcceptableContentType"),
              inheritanceClause: InheritanceClauseSyntax(typeNames: ["AcceptableProtocol"]),
              memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: MemberBlockItemListSyntax([
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      EnumCaseDeclSyntax(
                        leadingTrivia: [.newlines(1), .spaces(4)],
                        elements: EnumCaseElementListSyntax([
                          EnumCaseElementSyntax(name: .identifier("json"))
                        ])
                      ))),
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      EnumCaseDeclSyntax(
                        leadingTrivia: [.newlines(1), .spaces(4)],
                        elements: EnumCaseElementListSyntax([
                          EnumCaseElementSyntax(
                            name: .identifier("other"),
                            parameterClause: EnumCaseParameterClauseSyntax(
                              leftParen: .leftParenToken(),
                              parameters: EnumCaseParameterListSyntax([
                                EnumCaseParameterSyntax(
                                  type: TypeSyntax(
                                    MemberTypeSyntax(
                                      baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Swift"))),
                                      period: .periodToken(),
                                      name: .identifier("String")
                                    ))
                                )
                              ]),
                              rightParen: .rightParenToken()
                            )
                          )
                        ])
                      ))),
                  MemberBlockItemSyntax(
                    decl: DeclSyntax(
                      InitializerDeclSyntax(
                        modifiers: DeclModifierListSyntax([
                          DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.newlines(1), .spaces(4)]))
                        ]),
                        initKeyword: .keyword(.`init`),
                        optionalMark: .postfixQuestionMarkToken(),
                        signature: FunctionSignatureSyntax(
                          parameterClause: FunctionParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: FunctionParameterListSyntax([
                              FunctionParameterSyntax(
                                firstName: .identifier("rawValue"),
                                colon: .colonToken(),
                                type: MemberTypeSyntax(
                                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Swift"))),
                                  period: .periodToken(),
                                  name: .identifier("String")
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
                                ExpressionStmtSyntax(
                                  expression: ExprSyntax(
                                    SwitchExprSyntax(
                                      leadingTrivia: [.newlines(1), .spaces(6)],
                                      subject: FunctionCallExprSyntax(
                                        callee: ExprSyntax(
                                          MemberAccessExprSyntax(
                                            base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue"))),
                                            period: .periodToken(),
                                            declName: DeclReferenceExprSyntax(baseName: .identifier("lowercased"))
                                          )
                                        )
                                      )
                                    ) {
                                      SwitchCaseSyntax(
                                        label: SwitchCaseSyntax.Label(
                                          SwitchCaseLabelSyntax(
                                            leadingTrivia: [.newlines(1), .spaces(6)]) {
                                              SwitchCaseItemSyntax(
                                                pattern: PatternSyntax(
                                                  ExpressionPatternSyntax(
                                                    expression: ExprSyntax(
                                                      StringLiteralExprSyntax(content: "application/json")
                                                    ))
                                                ))
                                            })
                                      ) {
                                        SequenceExprSyntax {
                                          ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(8)])))
                                          ExprSyntax(AssignmentExprSyntax(equal: .equalToken()))
                                          ExprSyntax(
                                            MemberAccessExprSyntax(
                                              period: .periodToken(),
                                              declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                                            ))
                                        }
                                      }
                                      SwitchCaseSyntax(
                                        label: SwitchCaseSyntax.Label(
                                          SwitchDefaultLabelSyntax(
                                            leadingTrivia: [.newlines(1), .spaces(6)],
                                            colon: .colonToken()
                                          )),
                                        statements: CodeBlockItemListSyntax([
                                          CodeBlockItemSyntax(
                                            item: CodeBlockItemSyntax.Item(
                                              SequenceExprSyntax(
                                                elements: ExprListSyntax([
                                                  ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self, leadingTrivia: [.newlines(1), .spaces(8)]))),
                                                  ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                                                  ExprSyntax(
                                                    FunctionCallExprSyntax(
                                                      callee: ExprSyntax(
                                                        MemberAccessExprSyntax(
                                                          period: .periodToken(),
                                                          declName: DeclReferenceExprSyntax(baseName: .identifier("other"))
                                                        ))
                                                    ) {
                                                      LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue"))))
                                                    }
                                                  ),
                                                ]))))
                                        ])
                                      )
                                    }
                                    .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(6)]))
                                  ))))
                          ]),
                          rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                        )
                      ))),
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
                              type: TypeSyntax(
                                MemberTypeSyntax(
                                  baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Swift"))),
                                  period: .periodToken(),
                                  name: .identifier("String")
                                ))
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
                                            leadingTrivia: [.newlines(1), .spaces(6)],
                                            subject: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                                          ) {
                                            SwitchCaseSyntax(
                                              label: SwitchCaseSyntax.Label(
                                                SwitchCaseLabelSyntax(
                                                  leadingTrivia: [.newlines(1), .spaces(6)],
                                                  caseItems: SwitchCaseItemListSyntax([
                                                    SwitchCaseItemSyntax(
                                                      pattern: PatternSyntax(
                                                        ExpressionPatternSyntax(
                                                          expression: ExprSyntax(
                                                            FunctionCallExprSyntax(
                                                              callee: ExprSyntax(
                                                                MemberAccessExprSyntax(
                                                                  period: .periodToken(),
                                                                  declName: DeclReferenceExprSyntax(baseName: .identifier("other"))
                                                                ))
                                                            ) {
                                                              LabeledExprSyntax(
                                                                expression: ExprSyntax(
                                                                  PatternExprSyntax(
                                                                    pattern: PatternSyntax(
                                                                      ValueBindingPatternSyntax(
                                                                        bindingSpecifier: .keyword(.let),
                                                                        pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("string")))
                                                                      )))))
                                                            }
                                                          ))))
                                                  ]),
                                                  colon: .colonToken()
                                                ))
                                            ) {
                                              ReturnStmtSyntax(
                                                leadingTrivia: [.newlines(1), .spaces(8)],
                                                expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("string")))
                                              )
                                            }
                                            SwitchCaseSyntax(
                                              label: SwitchCaseSyntax.Label(
                                                SwitchCaseLabelSyntax(
                                                  leadingTrivia: [.newlines(1), .spaces(6)],
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
                                                )),
                                              statements: CodeBlockItemListSyntax([
                                                CodeBlockItemSyntax(
                                                  item: CodeBlockItemSyntax.Item(
                                                    ReturnStmtSyntax(
                                                      leadingTrivia: [.newlines(1), .spaces(8)],
                                                      expression: ExprSyntax(
                                                        StringLiteralExprSyntax(
                                                          openingQuote: .stringQuoteToken(),
                                                          segments: StringLiteralSegmentListSyntax([
                                                            StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("application/json")))
                                                          ]),
                                                          closingQuote: .stringQuoteToken()
                                                        ))
                                                    )))
                                              ])
                                            )
                                          }
                                          .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(6)]))
                                        ))))
                                ])),
                              rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                            )
                          )
                        ])
                      ))),
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
                                      ArrayExprSyntax(
                                        leadingTrivia: [.newlines(1), .spaces(6)],
                                        rightSquare: .rightSquareToken(leadingTrivia: [.newlines(1), .spaces(6)])
                                      ) {
                                        ArrayElementSyntax(
                                          expression: ExprSyntax(
                                            MemberAccessExprSyntax(
                                              period: .periodToken(leadingTrivia: [.newlines(1), .spaces(8)]),
                                              declName: DeclReferenceExprSyntax(baseName: .identifier("json"))
                                            )))
                                      }
                                    ))
                                ])),
                              rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                            )
                          )
                        ])
                      ))),
                ]),
                rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(2)])
              )
            )))
      }
      makeErrorDeclaration(leadingTrivia: [.newlines(1)], ts: ts, name: name, type: type)
    }
  }

  private func procedureInputInitializer(leadingTrivia: Trivia? = nil, typeName: String) -> InitializerDeclSyntax {
    var members: [(String, MemberTypeSyntax)] = [
      (
        "headers",
        MemberTypeSyntax(parts: [.identifier(typeName), .identifier("Input"), .identifier("Headers")])
      )
    ]
    if self.input != nil {
      members.append(
        (
          "body",
          MemberTypeSyntax(parts: [.identifier(typeName), .identifier("Input"), .identifier("Body")])
        ))
    }
    return memberInitializer(leadingTrivia: leadingTrivia, members: members)
  }
}
