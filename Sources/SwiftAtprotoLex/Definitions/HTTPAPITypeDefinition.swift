import Foundation
import SwiftSyntax

protocol HTTPAPITypeDefinition: Encodable, DecodableWithConfiguration, SwiftCodeGeneratable {
  associatedtype DecodingConfiguration = TypeSchema.DecodingConfiguration
  var type: FieldType { get }
  var parameters: Parameters? { get }
  var output: OutputType? { get }
  var input: InputType? { get }
  var description: String? { get }
  var errors: [ErrorResponse]? { get }

  var contentType: String { get }
  var inputRPCValue: ExprSyntax { get }
  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [FunctionParameterSyntax]
  func rpcOutput(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> ReturnClauseSyntax
  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol
}

private enum HTTPAPITypedCodingKeys: String, CodingKey {
  case type
  case parameters
  case output
  case input
  case description
}

extension HTTPAPITypeDefinition {
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: HTTPAPITypedCodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(parameters, forKey: .parameters)
    try container.encodeIfPresent(output, forKey: .output)
    try container.encodeIfPresent(input, forKey: .input)
    try container.encodeIfPresent(description, forKey: .description)
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

  var inputRPCValue: ExprSyntax {
    ExprSyntax(stringLiteral: input != nil ? "input" : "Bool?.none")
  }

  func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> [FunctionParameterSyntax] {
    var arguments = [FunctionParameterSyntax]()
    if let input {
      switch input.encoding {
      case .cbor, .any, .car, .mp4:
        let tname = "Data"
        let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
      case .text:
        let tname = "String"
        let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
      case .json, .jsonl:
        let tname: String
        if case .ref(let ref) = input.schema?.type {
          (_, tname) = ts.namesFromRef(ref: ref.ref, defMap: defMap)
        } else {
          tname = "\(fname)_Input"
        }
        let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: "\(prefix).\(tname)"), trailingComma: comma))
      }
    }

    if let parameters {
      var required = [String: Bool]()
      for req in parameters.required ?? [] {
        required[req] = true
      }
      let count = parameters.properties.count
      var i = 0
      for (name, t) in parameters.sortedProperties {
        i += 1
        let isRequired = required[name] ?? false
        let tn: String
        if case .string(let def) = t, def.enum != nil || def.knownValues != nil {
          tn = "\(prefix).\(fname)_\(name.titleCased())"
        } else {
          let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
          tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, dropPrefix: false)
        }
        let type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(tn)))
        let comma: TokenSyntax? = i == count ? nil : .commaToken()
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
              : TypeSyntax(OptionalTypeSyntax(wrappedType: type)), defaultValue: defaultValue, trailingComma: comma))
      }
    }
    return arguments
  }

  func rpcOutput(ts: TypeSchema, fname: String, defMap: ExtDefMap, prefix: String) -> ReturnClauseSyntax {
    if let output {
      switch output.encoding {
      case .json, .jsonl:
        guard let schema = output.schema else {
          return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "EmptyResponse"))
        }
        let outname: String
        if case .ref(let def) = schema.type {
          (_, outname) = ts.namesFromRef(ref: def.ref, defMap: defMap)
        } else {
          outname = "\(fname)_Output"
        }
        return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "\(prefix).\(outname)"))
      case .text:
        return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "String"))
      case .cbor, .car, .any, .mp4:
        return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "Data"))
      }
    }
    return ReturnClauseSyntax(type: TypeSyntax("Bool"))
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

  func generateDeclaration(leadingTrivia: Trivia?, ts: TypeSchema, name typeName: String, type: String, defMap _: ExtDefMap) -> any DeclSyntaxProtocol {
    return EnumDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier(ts.typeName)
    ) {
      makeErrorDeclaration(leadingTrivia: .spaces(4), ts: ts, name: typeName, type: type)
    }
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
