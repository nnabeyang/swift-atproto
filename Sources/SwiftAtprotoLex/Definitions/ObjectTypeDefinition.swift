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
    return StructDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      name: .init(stringLiteral: ts.isRecord ? "\(Lex.structNameFor(prefix: ts.prefix))_\(name)" : name),
      inheritanceClause: InheritanceClauseSyntax(typeNames: ts.isRecord ? ["ATProtoRecord"] : ["Codable", "Hashable", "Sendable"])
    ) {
      if ts.isRecord {
        VariableDeclSyntax(
          leadingTrivia: [.newlines(1), .spaces(4)],
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
                value: StringLiteralExprSyntax(
                  openingQuote: .stringQuoteToken(),
                  segments: StringLiteralSegmentListSyntax([
                    StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(typeName)))
                  ]),
                  closingQuote: .stringQuoteToken()
                )
              )
            )
          ])
        )
        VariableDeclSyntax(
          leadingTrivia: [.newlines(1), .spaces(4)],
          modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.public))
          ]),
          bindingSpecifier: .keyword(.var),
          bindings: [
            PatternBindingSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("type")),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: IdentifierTypeSyntax(name: .identifier("String"))
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
        let type = ts.typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: !ts.isRecord)
        property.variable(name: key, type: type, isMutable: !ts.isRecord)
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
                key: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                colon: .colonToken(),
                value: TypeSyntax(IdentifierTypeSyntax(name: .identifier("AnyCodable"))),
                rightSquare: .rightSquareToken()
              )
            )
          )
        ]
      )
      InitializerDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        signature: FunctionSignatureSyntax(
          parameterClause: FunctionParameterClauseSyntax {
            for (key, property) in sortedProperties {
              let isRequired = required[key] ?? false
              let defaultValue: InitializerClauseSyntax? =
                isRequired
                ? nil
                : InitializerClauseSyntax(
                  equal: .equalToken(),
                  value: NilLiteralExprSyntax()
                )
              let type = ts.typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: !ts.isRecord)
              FunctionParameterSyntax(firstName: .identifier(key), type: type, defaultValue: defaultValue)
            }
          }
        )
      ) {
        for (key, _) in sortedProperties {
          SequenceExprSyntax {
            MemberAccessExprSyntax(
              base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
              period: .periodToken(),
              declName: DeclReferenceExprSyntax(baseName: .identifier(key))
            )
            AssignmentExprSyntax(equal: .equalToken())
            DeclReferenceExprSyntax(baseName: .identifier(key.escapedSwiftKeyword))
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
      if !enumCaseIsEmpty {
        EnumDeclSyntax(
          leadingTrivia: .newlines(2),
          name: "CodingKeys",
          inheritanceClause: InheritanceClauseSyntax(typeNames: ["String", "CodingKey"])
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
              return ts.isRecord ? "\(Lex.structNameFor(prefix: ts.prefix)).\(tname)" : tname
            } else {
              let cts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: key, type: property)
              return TypeSchema.typeNameForField(name: name, k: key, v: cts, defMap: defMap, dropPrefix: !ts.isRecord)
            }
          }()
          SequenceExprSyntax {
            MemberAccessExprSyntax(
              base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
              period: .periodToken(),
              declName: DeclReferenceExprSyntax(baseName: .identifier(key))
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
                    base: DeclReferenceExprSyntax(baseName: .identifier(tname)),
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
                    declName: DeclReferenceExprSyntax(baseName: .identifier(key))
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
                          key: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("String"))),
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
                  declName: DeclReferenceExprSyntax(baseName: .identifier(key))
                ),
                trailingComma: .commaToken()
              )
              LabeledExprSyntax(
                label: .identifier("forKey"),
                colon: .colonToken(),
                expression: MemberAccessExprSyntax(
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier(key))
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
}
