import Foundation
import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

struct ObjectTypeDefinition: Encodable, DecodableWithConfiguration, SwiftCodeGeneratable {
  typealias DecodingConfiguration = TypeSchema.DecodingConfiguration

  var type: FieldType { .object }
  let description: String?
  let properties: [String: FieldTypeDefinition]
  let required: [String]?
  let nullable: [String]?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case properties
    case required
    case nullable
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: TypedCodingKeys.self)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    let nestedContainer = try container.nestedContainer(keyedBy: AnyCodingKeys.self, forKey: .properties)
    var properties = [String: FieldTypeDefinition]()
    for key in nestedContainer.allKeys {
      properties[key.stringValue] = try nestedContainer.decode(FieldTypeDefinition.self, forKey: key, configuration: configuration)
    }
    self.properties = properties
    required = try container.decodeIfPresent([String].self, forKey: .required)
    nullable = try container.decodeIfPresent([String].self, forKey: .nullable)
  }

  var sortedProperties: [(String, FieldTypeDefinition)] {
    properties.keys.sorted().compactMap {
      guard let property = properties[$0] else { return nil }
      return ($0, property)
    }
  }

  private var declModifierSyntax: DeclModifierSyntax {
    guard let description else { return DeclModifierSyntax(name: .keyword(.public)) }
    return DeclModifierSyntax(name: .keyword(.public, leadingTrivia: [.docLineComment("/// \(description)"), .newlines(1)]))
  }

  func generateDeclaration(
    leadingTrivia: Trivia? = nil, ts: TypeSchema, name: String, type typeName: String,
    defMap: ExtDefMap, generate: GenerateOption
  ) -> any DeclSyntaxProtocol {
    var required = [String: Bool]()
    for req in self.required ?? [] {
      required[req] = true
    }
    let sortedKeys = properties.keys.sorted()
    let enumCaseIsEmpty = sortedKeys.isEmpty && !ts.isRecord
    for key in nullable ?? [] {
      required[key] = false
    }
    let hasConstraints = sortedProperties.contains { $0.1.hasConstraints }
    let repoWriteAction = Self.repoWriteAction(nsid: ts.id, inputName: name)
    let inheritedNames: [String] = {
      if ts.isRecord { return ["ATProtoRecord"] }
      var names = ["Codable", "Hashable", "Sendable"]
      if repoWriteAction != nil {
        names.append("RepoWriteOperationDescribing")
      }
      return names
    }()
    return StructDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [declModifierSyntax],
      name: .lexIdentifier(name),
      inheritanceClause: InheritanceClauseSyntax(typeNames: inheritedNames)
    ) {
      if ts.isRecord {
        VariableDeclSyntax(
          leadingTrivia: .newline,
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public)),
            DeclModifierSyntax(name: .keyword(.static)),
          ]),
          bindingSpecifier: .keyword(.let),
          bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("nsId"))),
              initializer: InitializerClauseSyntax(
                equal: .equalToken(),
                value: StringLiteralExprSyntax(content: typeName),
              )
            )
          ])
        )
        VariableDeclSyntax(
          leadingTrivia: .newline,
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public))
          ]),
          bindingSpecifier: .keyword(.var),
          bindings: [
            PatternBindingSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("type")),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: Lex.typeSyntax("Swift.String")
              ),
              accessorBlock: AccessorBlockSyntax(
                leftBrace: .leftBraceToken(),
                accessors: AccessorBlockSyntax.Accessors(
                  [
                    CodeBlockItemSyntax(
                      item: CodeBlockItemSyntax.Item(
                        MemberAccessExprSyntax(
                          base: DeclReferenceExprSyntax(baseName: .keyword(.Self)),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("nsId"))
                        )))
                  ]),
                rightBrace: .rightBraceToken()
              )
            )
          ]
        )
      }
      for (key, property) in sortedProperties {
        let isRequired = required[key] ?? false
        let type = ts.typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: true)
        let docTrivia: Trivia? = property.lexDescription.map {
          Trivia(pieces: [.docLineComment("/// \($0)"), .newlines(1)])
        }
        property.variable(name: key, type: type, isMutable: !ts.isRecord, leadingTrivia: docTrivia)
      }
      VariableDeclSyntax(
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        bindingSpecifier: .keyword(.let),
        bindings: [
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("_unknownValues")),
            typeAnnotation: TypeAnnotationSyntax(
              colon: .colonToken(),
              type: DictionaryTypeSyntax(
                leftSquare: .leftSquareToken(),
                key: Lex.typeSyntax("Swift.String"),
                colon: .colonToken(),
                value: TypeSyntax(IdentifierTypeSyntax(name: .identifier("AnyCodable"))),
                rightSquare: .rightSquareToken()
              )
            )
          )
        ]
      )
      memberwiseInitDecl(ts: ts, name: name, defMap: defMap, required: required)
        .with(\.leadingTrivia, .newlines(2))
      if hasConstraints {
        staticMakeDecl(ts: ts, name: name, defMap: defMap, required: required)
          .with(\.leadingTrivia, .newlines(2))
      }
      if let actionRaw = repoWriteAction {
        Self.repoWriteRequirementsAccessor(actionRaw: actionRaw)
          .with(\.leadingTrivia, .newlines(2))
      }
      if !enumCaseIsEmpty {
        EnumDeclSyntax(
          leadingTrivia: .newlines(2),
          name: "CodingKeys",
          inheritanceClause: InheritanceClauseSyntax(typeNames: ["Swift.String", "CodingKey"])
        ) {
          if ts.isRecord {
            EnumCaseDeclSyntax {
              EnumCaseElementSyntax(
                name: "type",
                rawValue: InitializerClauseSyntax(
                  value: StringLiteralExprSyntax(content: "$type")
                ))
            }
          }
          for key in sortedKeys {
            EnumCaseDeclSyntax {
              EnumCaseElementSyntax(name: .identifier(key.escapedSwiftKeyword))
            }
          }
        }
      }
      if hasConstraints {
        constraintDecodableInitDecl(ts: ts, name: name, defMap: defMap, required: required)
          .with(\.leadingTrivia, .newlines(2))
      } else {
        decodableInitializerDeclSyntax(leadingTrivia: .newlines(2)) {
          if !enumCaseIsEmpty {
            VariableDeclSyntax(
              bindingSpecifier: .keyword(.let),
              bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                  pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("keyedContainer"))),
                  initializer: InitializerClauseSyntax(
                    equal: .equalToken(),
                    value: TryExprSyntax(
                      expression: FunctionCallExprSyntax(
                        callee: MemberAccessExprSyntax(
                          base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("decoder"))),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                        )
                      ) {
                        LabeledExprSyntax(
                          label: .identifier("keyedBy"),
                          colon: .colonToken(),
                          expression: ExprSyntax(
                            MemberAccessExprSyntax(
                              base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                              period: .periodToken(),
                              declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                            ))
                        )
                      }
                    )
                  )
                )
              ])
            )
          }
          for (key, property) in sortedProperties {
            let isRequired = required[key] ?? false
            let tname: String = {
              if case .string(let def) = property, def.enum != nil || def.knownValues != nil {
                let tname = "\(name)_\(key.titleCased())"
                return "\(Lex.structNameFor(prefix: ts.prefix)).\(tname)"
              } else {
                let cts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: key, type: property)
                return TypeSchema.typeNameForField(name: name, k: key, v: cts, defMap: defMap, dropPrefix: true)
              }
            }()
            SequenceExprSyntax {
              MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
              )
              AssignmentExprSyntax(equal: .equalToken())
              TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("keyedContainer")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(isRequired ? "decode" : "decodeIfPresent"))
                  )
                ) {
                  LabeledExprSyntax(
                    expression: MemberAccessExprSyntax(
                      base: Lex.refExpr(tname),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                    ),
                    trailingComma: .commaToken()
                  )
                  LabeledExprSyntax(
                    label: .identifier("forKey"),
                    colon: .colonToken(),
                    expression: MemberAccessExprSyntax(
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
                    )
                  )
                }
              )
            }
          }
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.let),
            bindings: [
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("unknownContainer")),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: TryExprSyntax(
                    expression: FunctionCallExprSyntax(
                      callee: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                      )
                    ) {
                      LabeledExprSyntax(
                        label: .identifier("keyedBy"),
                        colon: .colonToken(),
                        expression: ExprSyntax(
                          MemberAccessExprSyntax(
                            base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("AnyCodingKeys"))),
                            period: .periodToken(),
                            declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                          ))
                      )
                    }
                  )
                )
              )
            ]
          )
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.var),
            bindings: [
              PatternBindingSyntax(
                pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("_unknownValues"))),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: FunctionCallExprSyntax(
                    callee: DictionaryExprSyntax(
                      leftSquare: .leftSquareToken(),
                      content: DictionaryExprSyntax.Content(
                        DictionaryElementListSyntax([
                          DictionaryElementSyntax(
                            key: Lex.refExpr("Swift.String"),
                            colon: .colonToken(),
                            value: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("AnyCodable")))
                          )
                        ])),
                      rightSquare: .rightSquareToken()
                    ))
                )
              )
            ]
          )
          ForStmtSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("key")),
            sequence: MemberAccessExprSyntax(
              base: DeclReferenceExprSyntax(baseName: .identifier("unknownContainer")),
              period: .periodToken(),
              declName: DeclReferenceExprSyntax(baseName: .identifier("allKeys"))
            )
          ) {
            if !sortedKeys.isEmpty || ts.isRecord {
              GuardStmtSyntax(
                conditions: ConditionElementListSyntax {
                  SequenceExprSyntax {
                    FunctionCallExprSyntax(
                      callee: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys"))
                    ) {
                      LabeledExprSyntax(
                        label: .identifier("rawValue"),
                        colon: .colonToken(),
                        expression: MemberAccessExprSyntax(
                          base: DeclReferenceExprSyntax(baseName: .identifier("key")),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("stringValue"))
                        )
                      )
                    }
                    BinaryOperatorExprSyntax(operator: .binaryOperator("=="))
                    NilLiteralExprSyntax()
                  }
                }
              ) {
                ContinueStmtSyntax(continueKeyword: .keyword(.continue))
              }
            }
            SequenceExprSyntax {
              SubscriptCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(baseName: .identifier("_unknownValues"))
              ) {
                LabeledExprSyntax(
                  expression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("key")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("stringValue"))
                  ))
              }
              AssignmentExprSyntax(equal: .equalToken())
              TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(parts: [.identifier("unknownContainer"), .identifier("decode")])
                ) {
                  LabeledExprSyntax(
                    expression: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("AnyCodable")),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                    )
                  )
                  LabeledExprSyntax(
                    label: .identifier("forKey"),
                    colon: .colonToken(),
                    expression: DeclReferenceExprSyntax(baseName: .identifier("key"))
                  )
                }
              )
            }
          }
          SequenceExprSyntax {
            MemberAccessExprSyntax(
              base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
              period: .periodToken(),
              declName: DeclReferenceExprSyntax(baseName: .identifier("_unknownValues"))
            )
            AssignmentExprSyntax(equal: .equalToken())
            DeclReferenceExprSyntax(baseName: .identifier("_unknownValues"))
          }
        }
      }
      encodableFunctionDeclSyntax(leadingTrivia: .newlines(2)) {
        if !properties.isEmpty {
          VariableDeclSyntax(
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
              PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                initializer: InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("encoder")),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                    )
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("keyedBy"),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      )
                    )
                  }
                )
              )
            ])
          )
        }
        for (key, _) in sortedProperties {
          let isRequired = required[key] ?? false
          TryExprSyntax(
            expression: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier(isRequired ? "encode" : "encodeIfPresent"))
              )
            ) {
              LabeledExprSyntax(
                expression: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
                ),
                trailingComma: .commaToken()
              )
              LabeledExprSyntax(
                label: .identifier("forKey"),
                colon: .colonToken(),
                expression: MemberAccessExprSyntax(
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
                )
              )
            }
          )
        }
        TryExprSyntax(
          expression: FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(
              base: DeclReferenceExprSyntax(baseName: .identifier("_unknownValues")),
              period: .periodToken(),
              declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
            )
          ) {
            LabeledExprSyntax(
              label: .identifier("to"),
              colon: .colonToken(),
              expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("encoder")))
            )
          }
        )
      }
    }
  }

  private func decodeTypeName(ts: TypeSchema, name: String, key: String, property: FieldTypeDefinition, defMap: ExtDefMap) -> String {
    if case .string(let def) = property, def.enum != nil || def.knownValues != nil {
      let tname = "\(name)_\(key.titleCased())"
      return "\(Lex.structNameFor(prefix: ts.prefix)).\(tname)"
    } else {
      let cts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: key, type: property)
      return TypeSchema.typeNameForField(name: name, k: key, v: cts, defMap: defMap, dropPrefix: true)
    }
  }

  private func memberwiseInitDecl(ts: TypeSchema, name: String, defMap: ExtDefMap, required: [String: Bool]) -> InitializerDeclSyntax {
    InitializerDeclSyntax(
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          for (key, property) in sortedProperties {
            let isRequired = required[key] ?? false
            let type = ts.typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: true)
            let defaultValue: InitializerClauseSyntax? =
              isRequired
              ? nil
              : InitializerClauseSyntax(equal: .equalToken(), value: NilLiteralExprSyntax())
            FunctionParameterSyntax(firstName: .lexIdentifier(key), type: type, defaultValue: defaultValue)
          }
        }
      )
    ) {
      for (key, _) in sortedProperties {
        SequenceExprSyntax {
          MemberAccessExprSyntax(
            base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
            period: .periodToken(),
            declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
          )
          AssignmentExprSyntax(equal: .equalToken())
          DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
        }
      }
      SequenceExprSyntax {
        MemberAccessExprSyntax(
          base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
          period: .periodToken(),
          declName: DeclReferenceExprSyntax(baseName: .identifier("_unknownValues"))
        )
        AssignmentExprSyntax(equal: .equalToken())
        DictionaryExprSyntax(
          leftSquare: .leftSquareToken(),
          content: DictionaryExprSyntax.Content(.colonToken()),
          rightSquare: .rightSquareToken()
        )
      }
    }
  }

  private func staticMakeDecl(ts: TypeSchema, name: String, defMap: ExtDefMap, required: [String: Bool]) -> FunctionDeclSyntax {
    FunctionDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.static)),
      ],
      name: .identifier("make"),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          for (key, property) in sortedProperties {
            let isRequired = required[key] ?? false
            let type = ts.typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: true)
            let defaultValue: InitializerClauseSyntax? =
              isRequired
              ? nil
              : InitializerClauseSyntax(equal: .equalToken(), value: NilLiteralExprSyntax())
            FunctionParameterSyntax(firstName: .lexIdentifier(key), type: type, defaultValue: defaultValue)
          }
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: ReturnClauseSyntax(
          type: TypeSyntax(IdentifierTypeSyntax(name: .keyword(.Self)))
        )
      )
    ) {
      for (key, property) in sortedProperties {
        let isRequired = required[key] ?? false
        for item in property.constraintGuardItems(for: key, optional: !isRequired) {
          item
        }
      }
      ReturnStmtSyntax(
        expression: FunctionCallExprSyntax(
          callee: MemberAccessExprSyntax(
            base: DeclReferenceExprSyntax(baseName: .keyword(.Self)),
            period: .periodToken(),
            declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
          )
        ) {
          for (key, _) in sortedProperties {
            LabeledExprSyntax(
              label: .lexIdentifier(key),
              colon: .colonToken(),
              expression: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
            )
          }
        }
      )
    }
  }

  private func constraintDecodableInitDecl(ts: TypeSchema, name: String, defMap: ExtDefMap, required: [String: Bool]) -> InitializerDeclSyntax {
    decodableInitializerDeclSyntax {
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
          PatternBindingSyntax(
            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("keyedContainer"))),
            initializer: InitializerClauseSyntax(
              equal: .equalToken(),
              value: TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("decoder"))),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                  )
                ) {
                  LabeledExprSyntax(
                    label: .identifier("keyedBy"),
                    colon: .colonToken(),
                    expression: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ))
                  )
                }
              )
            )
          )
        ])
      )
      for (key, property) in sortedProperties {
        let isRequired = required[key] ?? false
        let tname = decodeTypeName(ts: ts, name: name, key: key, property: property, defMap: defMap)
        VariableDeclSyntax(
          bindingSpecifier: .keyword(.let),
          bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
              pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .lexIdentifier(key))),
              initializer: InitializerClauseSyntax(
                equal: .equalToken(),
                value: TryExprSyntax(
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("keyedContainer")),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .identifier(isRequired ? "decode" : "decodeIfPresent"))
                    )
                  ) {
                    LabeledExprSyntax(
                      expression: MemberAccessExprSyntax(
                        base: Lex.refExpr(tname),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ),
                      trailingComma: .commaToken()
                    )
                    LabeledExprSyntax(
                      label: .identifier("forKey"),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
                      )
                    )
                  }
                )
              )
            )
          ])
        )
      }
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: [
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("unknownContainer")),
            initializer: InitializerClauseSyntax(
              equal: .equalToken(),
              value: TryExprSyntax(
                expression: FunctionCallExprSyntax(
                  callee: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                  )
                ) {
                  LabeledExprSyntax(
                    label: .identifier("keyedBy"),
                    colon: .colonToken(),
                    expression: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("AnyCodingKeys"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ))
                  )
                }
              )
            )
          )
        ]
      )
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.var),
        bindings: [
          PatternBindingSyntax(
            pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("_unknownValues"))),
            initializer: InitializerClauseSyntax(
              equal: .equalToken(),
              value: FunctionCallExprSyntax(
                callee: DictionaryExprSyntax(
                  leftSquare: .leftSquareToken(),
                  content: DictionaryExprSyntax.Content(
                    DictionaryElementListSyntax([
                      DictionaryElementSyntax(
                        key: Lex.refExpr("Swift.String"),
                        colon: .colonToken(),
                        value: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("AnyCodable")))
                      )
                    ])),
                  rightSquare: .rightSquareToken()
                ))
            )
          )
        ]
      )
      ForStmtSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier("key")),
        sequence: MemberAccessExprSyntax(
          base: DeclReferenceExprSyntax(baseName: .identifier("unknownContainer")),
          period: .periodToken(),
          declName: DeclReferenceExprSyntax(baseName: .identifier("allKeys"))
        )
      ) {
        GuardStmtSyntax(
          conditions: ConditionElementListSyntax {
            SequenceExprSyntax {
              FunctionCallExprSyntax(
                callee: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys"))
              ) {
                LabeledExprSyntax(
                  label: .identifier("rawValue"),
                  colon: .colonToken(),
                  expression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("key")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("stringValue"))
                  )
                )
              }
              BinaryOperatorExprSyntax(operator: .binaryOperator("=="))
              NilLiteralExprSyntax()
            }
          }
        ) {
          ContinueStmtSyntax(continueKeyword: .keyword(.continue))
        }
        SequenceExprSyntax {
          SubscriptCallExprSyntax(
            calledExpression: DeclReferenceExprSyntax(baseName: .identifier("_unknownValues"))
          ) {
            LabeledExprSyntax(
              expression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("key")),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("stringValue"))
              ))
          }
          AssignmentExprSyntax(equal: .equalToken())
          TryExprSyntax(
            expression: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(parts: [.identifier("unknownContainer"), .identifier("decode")])
            ) {
              LabeledExprSyntax(
                expression: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("AnyCodable")),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                )
              )
              LabeledExprSyntax(
                label: .identifier("forKey"),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("key"))
              )
            }
          )
        }
      }
      IfExprSyntax(
        conditions: ConditionElementListSyntax {
          PrefixOperatorExprSyntax(
            operator: .prefixOperator("!"),
            expression: FunctionCallExprSyntax(
              callee: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("LexiconDecodingMode")),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("shouldValidateConstraints"))
              )
            ) {
              LabeledExprSyntax(
                label: .identifier("in"),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("decoder"))
              )
            }
          )
        }
      ) {
        SequenceExprSyntax {
          DeclReferenceExprSyntax(baseName: .keyword(.self))
          AssignmentExprSyntax(equal: .equalToken())
          FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(
              base: DeclReferenceExprSyntax(baseName: .keyword(.Self)),
              period: .periodToken(),
              declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
            )
          ) {
            for (key, _) in sortedProperties {
              LabeledExprSyntax(
                label: .lexIdentifier(key),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
              )
            }
          }
        }
        ReturnStmtSyntax()
      }
      DoStmtSyntax(
        body: CodeBlockSyntax {
          SequenceExprSyntax {
            DeclReferenceExprSyntax(baseName: .keyword(.self))
            AssignmentExprSyntax(equal: .equalToken())
            TryExprSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .keyword(.Self)),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier("make"))
                )
              ) {
                for (key, _) in sortedProperties {
                  LabeledExprSyntax(
                    label: .lexIdentifier(key),
                    colon: .colonToken(),
                    expression: DeclReferenceExprSyntax(baseName: .lexIdentifier(key))
                  )
                }
              }
            )
          }
        },
        catchClauses: CatchClauseListSyntax {
          CatchClauseSyntax(
            catchItems: CatchItemListSyntax {
              CatchItemSyntax(
                pattern: PatternSyntax(
                  ValueBindingPatternSyntax(
                    bindingSpecifier: .keyword(.let),
                    pattern: PatternSyntax(
                      ExpressionPatternSyntax(
                        expression: SequenceExprSyntax {
                          PatternExprSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("error"))
                          )
                          UnresolvedAsExprSyntax()
                          TypeExprSyntax(type: IdentifierTypeSyntax(name: .identifier("LexiconConstraintError")))
                        }
                      )
                    )
                  )
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
                  expression: FunctionCallExprSyntax(
                    callee: MemberAccessExprSyntax(
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
                    )
                  ) {
                    LabeledExprSyntax(
                      label: .identifier("codingPath"),
                      colon: .colonToken(),
                      expression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("codingPath"))
                      )
                    )
                    LabeledExprSyntax(
                      label: .identifier("debugDescription"),
                      colon: .colonToken(),
                      expression: StringLiteralExprSyntax(
                        openingQuote: .stringQuoteToken(),
                        segments: StringLiteralSegmentListSyntax {
                          ExpressionSegmentSyntax(
                            expressions: LabeledExprListSyntax {
                              LabeledExprSyntax(
                                expression: DeclReferenceExprSyntax(baseName: .identifier("error"))
                              )
                            }
                          )
                        },
                        closingQuote: .stringQuoteToken()
                      )
                    )
                    LabeledExprSyntax(
                      label: .identifier("underlyingError"),
                      colon: .colonToken(),
                      expression: DeclReferenceExprSyntax(baseName: .identifier("error"))
                    )
                  }
                )
              }
            )
          }
        }
      )
    }
  }

  private static func repoWriteAction(nsid: String, inputName: String) -> String? {
    guard inputName.hasSuffix("_Input") else { return nil }
    switch nsid {
    case "com.atproto.repo.createRecord": return "create"
    case "com.atproto.repo.putRecord": return "update"
    case "com.atproto.repo.deleteRecord": return "delete"
    default: return nil
    }
  }

  private static func repoWriteRequirementsAccessor(actionRaw: String) -> VariableDeclSyntax {
    VariableDeclSyntax(
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      bindingSpecifier: .keyword(.var),
      bindings: [
        PatternBindingSyntax(
          pattern: IdentifierPatternSyntax(identifier: .identifier("repoWriteRequirements")),
          typeAnnotation: TypeAnnotationSyntax(
            type: ArrayTypeSyntax(
              element: IdentifierTypeSyntax(name: .identifier("RepoWriteRequirement"))
            )
          ),
          accessorBlock: AccessorBlockSyntax(
            leftBrace: .leftBraceToken(),
            accessors: AccessorBlockSyntax.Accessors([
              CodeBlockItemSyntax(
                item: CodeBlockItemSyntax.Item(
                  ArrayExprSyntax(
                    leftSquare: .leftSquareToken(),
                    elements: ArrayElementListSyntax([
                      ArrayElementSyntax(
                        expression: FunctionCallExprSyntax(
                          calledExpression: DeclReferenceExprSyntax(
                            baseName: .identifier("RepoWriteRequirement")),
                          leftParen: .leftParenToken(),
                          arguments: LabeledExprListSyntax([
                            LabeledExprSyntax(
                              label: .identifier("collection"),
                              colon: .colonToken(),
                              expression: MemberAccessExprSyntax(
                                base: DeclReferenceExprSyntax(baseName: .identifier("collection")),
                                period: .periodToken(),
                                declName: DeclReferenceExprSyntax(baseName: .identifier("rawValue"))
                              ),
                              trailingComma: .commaToken()
                            ),
                            LabeledExprSyntax(
                              label: .identifier("action"),
                              colon: .colonToken(),
                              expression: MemberAccessExprSyntax(
                                period: .periodToken(),
                                name: .identifier(actionRaw)
                              )
                            ),
                          ]),
                          rightParen: .rightParenToken()
                        )
                      )
                    ]),
                    rightSquare: .rightSquareToken()
                  )
                )
              )
            ]),
            rightBrace: .rightBraceToken()
          )
        )
      ]
    )
  }
}
