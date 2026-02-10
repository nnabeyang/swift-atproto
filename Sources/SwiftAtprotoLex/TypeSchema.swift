import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

struct TypeInfo {
  let name: String
  let type: TypeSchema
}

final class Schema: Encodable, DecodableWithConfiguration, Sendable {
  let prefix: String
  let lexicon: Int
  let id: String
  let revision: Int?
  let description: String?
  let defs: [String: TypeSchema]

  private enum CodingKeys: String, CodingKey {
    case lexicon
    case id
    case revision
    case description
    case defs
  }

  init(from decoder: any Decoder, configuration prefix: String) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.lexicon = try container.decode(Int.self, forKey: .lexicon)
    self.id = try container.decode(String.self, forKey: .id)
    self.revision = try container.decodeIfPresent(Int.self, forKey: .revision)
    self.description = try container.decodeIfPresent(String.self, forKey: .description)
    let nestedContainer = try container.nestedContainer(keyedBy: AnyCodingKeys.self, forKey: .defs)
    var defs = [String: TypeSchema]()
    for key in nestedContainer.allKeys {
      defs[key.stringValue] = try nestedContainer.decode(TypeSchema.self, forKey: key, configuration: .init(prefix: prefix, id: id, defName: key.stringValue))
    }
    self.defs = defs
    self.prefix = prefix
  }

  func allTypes(prefix: String) -> [String: TypeSchema] {
    var out = [String: TypeSchema]()
    let id = id
    var walk: ((String, TypeSchema?) -> Void)? = nil
    walk = { (name: String, ts: TypeSchema?) in
      guard let ts else {
        fatalError(#"nil type schema in "\#(name)"(\#(self.id)) "#)
      }
      switch ts.type {
      case .object(let def):
        out[name] = ts
        for (key, val) in def.properties {
          let childname = "\(name)_\(key.titleCased())"
          let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
          walk?(childname, ts)
        }
      case .union:
        out[name] = ts
      case .array(let def):
        let key = "\(name)_Elem"
        let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: def.items)
        walk?(key, ts)
      case .ref:
        break
      case .procedure(let def as any HTTPAPITypeDefinition), .query(let def as any HTTPAPITypeDefinition):
        if let input = def.input, let schema = input.schema {
          walk?("\(name)_Input", schema)
        }
        if let output = def.output, let schema = output.schema {
          walk?("\(name)_Output", schema)
        }
        if let parameters = def.parameters {
          for (key, val) in parameters.properties {
            let childname = "\(name)_\(key.titleCased())"
            let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
            walk?(childname, ts)
          }
        }
      case .record(let def):
        let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: "", type: .record(def))
        out[name] = ts
        for (key, val) in def.record.properties {
          let childname = "\(name)_\(key.titleCased())"
          let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
          walk?(childname, ts)
        }
      case .string(let def):
        guard def.knownValues != nil || def.enum != nil else { break }
        out[name] = ts
      default:
        break
      }
    }
    let tname = Lex.nameFromId(id: id, prefix: prefix)
    for elem in defs {
      let name = elem.key
      let n: String =
        if name == "main" {
          tname
        } else {
          "\(tname)_\(name.titleCased())"
        }
      walk?(n, elem.value)
    }
    return out
  }

  var name: String {
    let p = id.split(separator: ".")
    let count = p.count
    guard count >= 2 else { return p.first.map { String($0) } ?? "" }
    return "\(p[count - 2])\(p[count - 1])"
  }
}

typealias ExtDefMap = [String: ExtDef]

final class TypeSchema: Encodable, DecodableWithConfiguration, Sendable {
  struct DecodingConfiguration {
    let prefix: String
    let id: String
    let defName: String
  }

  enum CodingKeys: String, CodingKey {
    case type
  }

  let prefix: String
  let id: String
  let defName: String

  let type: FieldTypeDefinition

  var isRecord: Bool {
    switch type {
    case .record: true
    default: false
    }
  }

  init(id: String, prefix: String, defName: String, type: FieldTypeDefinition) {
    self.id = id
    self.prefix = prefix
    self.defName = defName
    self.type = type
  }

  required init(from decoder: Decoder, configuration: DecodingConfiguration) throws {
    type = try FieldTypeDefinition(from: decoder, configuration: configuration)

    id = configuration.id
    prefix = configuration.prefix
    defName = configuration.defName
  }

  func encode(to encoder: Encoder) throws {
    try type.encode(to: encoder)
  }

  func lookupRef(ref: String, defMap: ExtDefMap) -> TypeSchema {
    let fqref: String =
      if ref.hasPrefix("#") {
        "\(id)\(ref)"
      } else if ref.hasSuffix("#main") {
        String(ref.dropLast(5))
      } else {
        ref
      }
    guard let rr = defMap[fqref] else {
      fatalError("no such ref: \(fqref)")
    }
    let t = rr.type
    return t
  }

  func namesFromRef(ref: String, defMap: ExtDefMap, dropPrefix: Bool = true) -> (String, String) {
    let ts = lookupRef(ref: ref, defMap: defMap)
    if ts.prefix == "" {
      fatalError("no prefix for referenced type: \(ts.id)")
    }
    if prefix == "" {
      fatalError(#"no prefix for referencing type: \#(id) \#(defName)"#)
    }
    if case .string(let def) = ts.type, def.knownValues == nil, def.enum == nil {
      return ("INVALID", "String")
    }
    let tname: String =
      if ts.isRecord {
        "\(Lex.structNameFor(prefix: ts.prefix))_\(ts.typeName)"
      } else if dropPrefix, ts.prefix == prefix {
        ts.typeName
      } else {
        "\(Lex.structNameFor(prefix: ts.prefix)).\(ts.typeName)"
      }
    let vname: String =
      if tname.contains(where: { $0 == "." }) {
        String(tname.split(separator: ".")[1])
      } else {
        tname
      }
    return (vname, tname)
  }

  func writeErrorDecl(leadingTrivia: Trivia? = nil, def: any HTTPAPITypeDefinition, typeName: String, defMap _: ExtDefMap) -> DeclSyntaxProtocol {
    let errors = def.errors ?? []
    return EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.indirect)),
      ],
      name: .init(stringLiteral: "\(typeName)_Error"),
      inheritanceClause: InheritanceClauseSyntax {
        InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "XRPCError"))
      }
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
                modifiers: DeclModifierListSyntax([]),
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
                defaultKeyword: .keyword(.default),
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
              accessors: AccessorBlockSyntax.Accessors(
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
                            SwitchCaseLabelSyntax(
                              caseItems: [
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
                              ],
                              colon: .colonToken()
                            )),
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

  var typeName: String {
    guard !id.isEmpty else {
      fatalError("type schema hint fields not set")
    }
    guard !prefix.isEmpty else {
      fatalError("why no prefix?")
    }
    let baseType: String =
      if defName != "main" {
        "\(Lex.nameFromId(id: id, prefix: prefix))_\(defName.titleCased())"
      } else {
        Lex.nameFromId(id: id, prefix: prefix)
      }
    if case .array(let def) = type {
      if def.items.isPrimitive {
        return "[\(baseType)]"
      } else {
        return "[\(baseType)_Elem]"
      }
    } else {
      return baseType
    }
  }

  var isMethod: Bool {
    switch type {
    case .string, .object, .record, .subscription: false
    default: true
    }
  }

  static func typeNameForField(name: String, k: String, v: TypeSchema, defMap: ExtDefMap, dropPrefix: Bool = true) -> String {
    switch v.type {
    case .boolean:
      return "Bool"
    case .blob:
      return "LexBlob"
    case .bytes:
      return "Data"
    case .string(let def):
      if def.isPrimitive {
        return "String"
      }
      if !dropPrefix {
        return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
      } else {
        return "\(name)_\(k.titleCased())"
      }
    case .integer(let def):
      if def.isPrimitive {
        return "Int"
      }
      if !dropPrefix {
        return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
      } else {
        return "\(name)_\(k.titleCased())"
      }
    case .unknown:
      return "UnknownATPValue"
    case .cidLink:
      return "LexLink"
    case .ref(let def):
      let (_, tn) = v.namesFromRef(ref: def.ref, defMap: defMap, dropPrefix: dropPrefix)
      return tn
    case .array(let def):
      let ts = TypeSchema(id: v.id, prefix: v.prefix, defName: "Elem", type: def.items)
      let subt = Self.typeNameForField(name: "\(name)_\(k.titleCased())", k: "Elem", v: ts, defMap: defMap, dropPrefix: dropPrefix)
      return "[\(subt)]"
    case .union, .object:
      if !dropPrefix {
        return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
      } else {
        return "\(name)_\(k.titleCased())"
      }
    default:
      fatalError("field \(k) in \(name) has unsupported type name (\(v.type))")
    }
  }

  static func paramNameForField(typeSchema: TypeSchema) -> String {
    switch typeSchema.type {
    case .boolean:
      "bool"
    case .string:
      "string"
    case .integer:
      "integer"
    case .unknown:
      "_other"
    case .array:
      "array"
    default:
      fatalError()
    }
  }

  var httpMethod: String {
    switch type {
    case .procedure:
      ".post"
    case .query:
      ".get"
    default:
      fatalError()
    }
  }

  func writeRPC(leadingTrivia: Trivia? = nil, def: any HTTPAPITypeDefinition, typeName: String, defMap: ExtDefMap, prefix: String) -> DeclSyntaxProtocol {
    let fname = typeName
    let arguments = def.rpcArguments(ts: self, fname: fname, defMap: defMap, prefix: prefix)
    let output = def.rpcOutput(ts: self, fname: fname, defMap: defMap, prefix: prefix)
    return FunctionDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.mutating)),
      ],
      name: .identifier(typeName),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          arguments
        },
        effectSpecifiers: FunctionEffectSpecifiersSyntax(
          asyncSpecifier: .keyword(.async),
          throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        ),
        returnClause: output
      )
    ) {
      VariableDeclSyntax(
        bindingSpecifier: .keyword(.let)
      ) {
        if let params = def.rpcParams(id: id, prefix: prefix) {
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("params")),
            typeAnnotation: params is DictionaryExprSyntax
              ? TypeAnnotationSyntax(
                type: TypeSyntax(stringLiteral: "Parameters")
              ) : nil,
            initializer: InitializerClauseSyntax(
              value: params
            )
          )
        } else {
          PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier("params")),
            typeAnnotation: TypeAnnotationSyntax(
              type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("Bool")))
            ),
            initializer: InitializerClauseSyntax(
              value: NilLiteralExprSyntax()
            )
          )
        }
      }
      DoStmtSyntax(
        body: CodeBlockSyntax {
          ReturnStmtSyntax(
            expression: TryExprSyntax(
              expression:
                AwaitExprSyntax(
                  expression: FunctionCallExprSyntax(
                    callee: DeclReferenceExprSyntax(baseName: .identifier("fetch"))
                  ) {
                    LabeledExprSyntax(label: "endpoint", colon: .colonToken(), expression: StringLiteralExprSyntax(content: self.id), trailingComma: .commaToken())
                    LabeledExprSyntax(label: "contentType", colon: .colonToken(), expression: StringLiteralExprSyntax(content: def.contentType), trailingComma: .commaToken())
                    LabeledExprSyntax(label: "httpMethod", colon: .colonToken(), expression: ExprSyntax(stringLiteral: httpMethod), trailingComma: .commaToken())
                    LabeledExprSyntax(label: "params", colon: .colonToken(), expression: ExprSyntax("params"), trailingComma: .commaToken())
                    LabeledExprSyntax(label: "input", colon: .colonToken(), expression: def.inputRPCValue, trailingComma: .commaToken())
                    LabeledExprSyntax(label: "retry", colon: .colonToken(), expression: ExprSyntax("true"))
                  }
                )
            )
          )
        },
        catchClauses: [
          CatchClauseSyntax(
            CatchItemListSyntax {
              CatchItemSyntax(
                pattern: ValueBindingPatternSyntax(
                  bindingSpecifier: .keyword(.let),
                  pattern: ExpressionPatternSyntax(
                    expression: SequenceExprSyntax {
                      PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("error")))
                      UnresolvedAsExprSyntax()
                      TypeExprSyntax(type: IdentifierTypeSyntax(name: "UnExpectedError"))
                    }
                  )
                )
              )
            }
          ) {
            ThrowStmtSyntax(
              expression: FunctionCallExprSyntax(
                callee: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier(prefix)),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier("\(typeName)_Error"))
                )
              ) {
                LabeledExprSyntax(label: .identifier("error"), colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("error")))
              }
            )
          }
        ]
      )
    }
  }

  private func initializerParameters(name: String, def: ObjectTypeDefinition, required: [String: Bool], defMap: ExtDefMap, dropPrefix: Bool = true) -> [FunctionParameterSyntax] {
    var parameters = [FunctionParameterSyntax]()
    let properties = def.sortedProperties
    let count = properties.count
    var i = 0
    for (key, property) in properties {
      i += 1
      let isRequired = required[key] ?? false
      let comma: TokenSyntax? = i == count ? nil : .commaToken()
      let defaultValue: InitializerClauseSyntax? =
        isRequired
        ? nil
        : InitializerClauseSyntax(
          equal: .equalToken(),
          value: NilLiteralExprSyntax()
        )
      let type = typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: dropPrefix)
      parameters.append(.init(firstName: .identifier(key), type: type, defaultValue: defaultValue, trailingComma: comma))
    }

    return parameters
  }

  func typeIdentifier(name: String, property: FieldTypeDefinition, defMap: ExtDefMap, key: String, isRequired: Bool, dropPrefix: Bool = true) -> TypeSyntax {
    let type: TypeSyntax
    if case .string(let def) = property, def.enum != nil || def.knownValues != nil {
      let tn = "\(name)_\(key.titleCased())"
      type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(!dropPrefix ? "\(Lex.structNameFor(prefix: prefix)).\(tn)" : tn)))
    } else {
      let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: property)
      let tn = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, dropPrefix: dropPrefix)
      type = TypeSyntax(IdentifierTypeSyntax(name: .identifier(tn)))
    }
    if isRequired {
      return type
    } else {
      return TypeSyntax(OptionalTypeSyntax(wrappedType: type))
    }
  }

  func lex(leadingTrivia: Trivia? = nil, name: String, type typeName: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
    switch type {
    case .string(let def):
      if let knownValues = def.knownValues {
        genCodeStringWithKnownValues(leadingTrivia: leadingTrivia, name: name, knownValues: knownValues)
      } else if let cases = def.enum {
        genCodeStringWithEnum(leadingTrivia: leadingTrivia, name: name, cases: cases)
      } else {
        fatalError()
      }
    case .object(let def):
      genCodeObject(def: def, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
    case .record(let def):
      genCodeObject(def: def.record, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
    case .union(let def):
      genCodeUnion(def: def, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
    case .array(let def):
      genCodeArray(def: def, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
    default:
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
        inheritanceClause: InheritanceClauseSyntax(
          colon: .colonToken(),
          inheritedTypes: InheritedTypeListSyntax([
            InheritedTypeSyntax(
              type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
              trailingComma: .commaToken()
            ),
            InheritedTypeSyntax(
              type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable"))),
              trailingComma: .commaToken()
            ),
            InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Sendable")))),
          ])
        )
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
                    calledExpression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.Self))),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax([
                      LabeledExprSyntax(
                        label: .identifier("rawValue"),
                        colon: .colonToken(),
                        expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                      )
                    ]),
                    rightParen: .rightParenToken()
                  )
                )
              )
            },
            body: CodeBlockSyntax {
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
            })
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
      inheritanceClause: InheritanceClauseSyntax(
        colon: .colonToken(),
        inheritedTypes: [
          InheritedTypeSyntax(
            type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("RawRepresentable"))),
            trailingComma: .commaToken()
          ),
          InheritedTypeSyntax(
            type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable"))),
            trailingComma: .commaToken()
          ),
          InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Sendable")))),
        ]
      )
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
              SwitchCaseListSyntax.Element(
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
              )
            }
            SwitchCaseListSyntax.Element(
              SwitchCaseSyntax(
                label: SwitchCaseSyntax.Label(
                  SwitchDefaultLabelSyntax(
                    defaultKeyword: .keyword(.default),
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
                            declName: DeclReferenceExprSyntax(baseName: .identifier("_other"))
                          )
                        ) {
                          LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                        }
                      }
                    ))
                ])
              ))
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
                          switchKeyword: .keyword(.switch),
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
                                              calledExpression: MemberAccessExprSyntax(
                                                period: .periodToken(),
                                                declName: DeclReferenceExprSyntax(baseName: .identifier("_other"))
                                              ),
                                              leftParen: .leftParenToken(),
                                              arguments: LabeledExprListSyntax([
                                                LabeledExprSyntax(expression: PatternExprSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier("value"))))
                                              ]),
                                              rightParen: .rightParenToken()
                                            )))
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
                  tryKeyword: .keyword(.try),
                  expression: FunctionCallExprSyntax(
                    calledExpression: DeclReferenceExprSyntax(baseName: .identifier("String")),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax([
                      LabeledExprSyntax(
                        label: .identifier("from"),
                        colon: .colonToken(),
                        expression: DeclReferenceExprSyntax(baseName: .identifier("decoder"))
                      )
                    ]),
                    rightParen: .rightParenToken()
                  )
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
          tryKeyword: .keyword(.try),
          expression: FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
              MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("rawValue")),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
              )),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
              LabeledExprSyntax(
                label: .identifier("to"),
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier("encoder"))
              )
            ]),
            rightParen: .rightParenToken()
          )
        )
      }
    }
  }

  private func genCodeObject(def: ObjectTypeDefinition, leadingTrivia: Trivia? = nil, name: String, type typeName: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
    var required = [String: Bool]()
    for req in def.required ?? [] {
      required[req] = true
    }
    let sortedKeys = def.properties.keys.sorted()
    let enumCaseIsEmpty = sortedKeys.isEmpty && !isRecord
    let inherits: InheritedTypeListSyntax =
      if isRecord {
        [
          .init(type: IdentifierTypeSyntax(name: .identifier("ATProtoRecord")))
        ]
      } else {
        [
          InheritedTypeSyntax(
            type: IdentifierTypeSyntax(name: .identifier("Codable")),
            trailingComma: .commaToken()
          ),
          InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("Sendable"))),
        ]
      }
    for key in def.nullable ?? [] {
      required[key] = false
    }
    return StructDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [DeclModifierSyntax(name: .keyword(.public))],
      structKeyword: .keyword(.struct),
      name: .init(stringLiteral: isRecord ? "\(Lex.structNameFor(prefix: prefix))_\(name)" : name),
      inheritanceClause: InheritanceClauseSyntax(
        colon: .colonToken(),
        inheritedTypes: inherits
      )
    ) {
      if isRecord {
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
      for (key, property) in def.sortedProperties {
        let isRequired = required[key] ?? false
        let type = typeIdentifier(name: name, property: property, defMap: defMap, key: key, isRequired: isRequired, dropPrefix: !isRecord)
        property.variable(name: key, type: type, isMutable: !isRecord)
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
            initializerParameters(name: name, def: def, required: required, defMap: defMap, dropPrefix: !isRecord)
          }
        )
      ) {
        for (key, _) in def.sortedProperties {
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
          inheritanceClause: InheritanceClauseSyntax {
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "String"))
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "CodingKey"))
          }
        ) {
          if isRecord {
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
                      calledExpression: MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("decoder"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                      ),
                      leftParen: .leftParenToken(),
                      arguments: [
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
                      ],
                      rightParen: .rightParenToken()
                    )
                  )
                )
              )
            ])
          )
        }
        for (key, property) in def.sortedProperties {
          let isRequired = required[key] ?? false
          let tname: String = {
            if case .string(let def) = property, def.enum != nil || def.knownValues != nil {
              let tname = "\(name)_\(key.titleCased())"
              return isRecord ? "\(Lex.structNameFor(prefix: self.prefix)).\(tname)" : tname
            } else {
              let ts = TypeSchema(id: self.id, prefix: prefix, defName: key, type: property)
              return Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, dropPrefix: !isRecord)
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
                  tryKeyword: .keyword(.try),
                  expression: FunctionCallExprSyntax(
                    calledExpression: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .identifier("container"))
                    ),
                    leftParen: .leftParenToken(),
                    arguments: [
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
                    ],
                    rightParen: .rightParenToken()
                  )
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
                value: ExprSyntax(
                  FunctionCallExprSyntax(
                    calledExpression: DictionaryExprSyntax(
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
                    ),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax([]),
                    rightParen: .rightParenToken()
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
          if !sortedKeys.isEmpty || isRecord {
            GuardStmtSyntax(
              conditions: ConditionElementListSyntax {
                SequenceExprSyntax {
                  FunctionCallExprSyntax(
                    calledExpression: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax([
                      LabeledExprSyntax(
                        label: .identifier("rawValue"),
                        colon: .colonToken(),
                        expression: MemberAccessExprSyntax(
                          base: DeclReferenceExprSyntax(baseName: .identifier("key")),
                          period: .periodToken(),
                          declName: DeclReferenceExprSyntax(baseName: .identifier("stringValue"))
                        )
                      )
                    ]),
                    rightParen: .rightParenToken()
                  )
                  BinaryOperatorExprSyntax(operator: .binaryOperator("=="))
                  NilLiteralExprSyntax()
                }
              },
              elseKeyword: .keyword(.else),
              body: CodeBlockSyntax(
                leftBrace: .leftBraceToken(),
                statements: CodeBlockItemListSyntax([
                  CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ContinueStmtSyntax(continueKeyword: .keyword(.continue))))
                ]),
                rightBrace: .rightBraceToken()
              )
            )
          }
          SequenceExprSyntax {
            SubscriptCallExprSyntax(
              calledExpression: DeclReferenceExprSyntax(baseName: .identifier("_unknownValues")),
              leftSquare: .leftSquareToken(),
              arguments: LabeledExprListSyntax([
                LabeledExprSyntax(
                  expression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("key")),
                    period: .periodToken(),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("stringValue"))
                  ))
              ]),
              rightSquare: .rightSquareToken()
            )
            AssignmentExprSyntax(equal: .equalToken())
            TryExprSyntax(
              expression: FunctionCallExprSyntax(
                calledExpression: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("unknownContainer")),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: .identifier("decode"))
                ),
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                  LabeledExprSyntax(
                    expression: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("AnyCodable")),
                      period: .periodToken(),
                      declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                    ),
                    trailingComma: .commaToken()
                  ),
                  LabeledExprSyntax(
                    label: .identifier("forKey"),
                    colon: .colonToken(),
                    expression: DeclReferenceExprSyntax(baseName: .identifier("key"))
                  ),
                ]),
                rightParen: .rightParenToken()
              )
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
        if !def.properties.isEmpty {
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
        for (key, _) in def.sortedProperties {
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

  private func genCodeUnion(def: UnionTypeDefinition, leadingTrivia: Trivia? = nil, name: String, type _: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
    var tss = [TypeSchema]()
    for ref in def.refs {
      let refName: String =
        if ref.first == "#" {
          "\(id)\(ref)"
        } else {
          ref
        }
      if let ts = defMap[refName]?.type {
        tss.append(ts)
      }
    }

    return EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public)),
        DeclModifierSyntax(name: .keyword(.indirect)),
      ],
      name: .init(stringLiteral: name),
      inheritanceClause: InheritanceClauseSyntax(
        colon: .colonToken(),
        inheritedTypes: InheritedTypeListSyntax([
          InheritedTypeSyntax(
            type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable"))),
            trailingComma: .commaToken()
          ),
          InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Sendable")))),
        ])
      )
    ) {
      for ts in tss {
        let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
        let tn: TypeSyntaxProtocol =
          ts.prefix == prefix
          ? IdentifierTypeSyntax(name: .identifier(ts.typeName))
          : MemberTypeSyntax(
            baseType: IdentifierTypeSyntax(name: .identifier(Lex.structNameFor(prefix: ts.prefix))),
            period: .periodToken(),
            name: .identifier(ts.typeName)
          )

        EnumCaseDeclSyntax {
          EnumCaseElementSyntax(
            name: .identifier(Lex.caseNameFromId(id: id, prefix: prefix)),
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
        inheritanceClause: InheritanceClauseSyntax {
          InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "String"))
          InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "CodingKey"))
        }
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
                  calledExpression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                    name: .identifier("container")
                  ),
                  leftParen: .leftParenToken(),
                  arguments: .init([
                    LabeledExprSyntax(
                      label: "keyedBy", colon: .colonToken(),
                      expression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                        name: .keyword(.self)
                      ))
                  ]),
                  rightParen: .rightParenToken()
                )
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
                  calledExpression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                    name: .identifier("decode")
                  ),
                  leftParen: .leftParenToken(),
                  arguments: .init([
                    LabeledExprSyntax(
                      expression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("String")),
                        name: .keyword(.self)
                      ), trailingComma: .commaToken()),
                    LabeledExprSyntax(label: "forKey", colon: .colonToken(), expression: MemberAccessExprSyntax(name: "type")),
                  ]),
                  rightParen: .rightParenToken()
                )
              )
            )
          )
        }

        SwitchExprSyntax(subject: ExprSyntax("type")) {
          for ts in tss {
            let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
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
                    calledExpression: MemberAccessExprSyntax(
                      name: .identifier(Lex.caseNameFromId(id: id, prefix: prefix))
                    ),
                    leftParen: .leftParenToken(),
                    arguments: .init([
                      LabeledExprSyntax(
                        expression: FunctionCallExprSyntax(
                          calledExpression: MemberAccessExprSyntax(
                            name: .keyword(.`init`)
                          ),
                          leftParen: .leftParenToken(),
                          arguments: .init([
                            LabeledExprSyntax(label: "from", colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("decoder")))
                          ]),
                          rightParen: .rightParenToken()
                        ))
                    ]),
                    rightParen: .rightParenToken()
                  )
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
                  calledExpression: ExprSyntax("._other"),
                  leftParen: .leftParenToken(),
                  arguments: .init([
                    LabeledExprSyntax(
                      expression: FunctionCallExprSyntax(
                        calledExpression: ExprSyntax(".init"),
                        leftParen: .leftParenToken(),
                        arguments: .init([
                          LabeledExprSyntax(label: "from", colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("decoder")))
                        ]),
                        rightParen: .rightParenToken()
                      ))
                  ]),
                  rightParen: .rightParenToken()
                )
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
                calledExpression: MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .identifier("encoder")),
                  name: .identifier("container")
                ),
                leftParen: .leftParenToken(),
                arguments: .init([
                  LabeledExprSyntax(
                    label: "keyedBy", colon: .colonToken(),
                    expression: MemberAccessExprSyntax(
                      base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                      name: .keyword(.self)
                    ))
                ]),
                rightParen: .rightParenToken()
              )
            )
          )
        }

        SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
          for ts in tss {
            let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
            SwitchCaseSyntax(
              label: .case(
                .init(caseItems: [
                  .init(
                    pattern: ValueBindingPatternSyntax(
                      bindingSpecifier: .keyword(.let),
                      pattern: ExpressionPatternSyntax(
                        expression: FunctionCallExprSyntax(
                          calledExpression: MemberAccessExprSyntax(name: .identifier(Lex.caseNameFromId(id: id, prefix: prefix))),
                          leftParen: .leftParenToken(),
                          arguments: LabeledExprListSyntax([
                            .init(
                              expression: PatternExprSyntax(
                                pattern: IdentifierPatternSyntax(identifier: .identifier("value"))
                              )
                            )
                          ]),
                          rightParen: .rightParenToken()
                        )
                      )
                    ))
                ])
              )
            ) {
              TryExprSyntax(
                tryKeyword: .keyword(.try),
                expression: ExprSyntax(
                  FunctionCallExprSyntax(
                    calledExpression: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                      )),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax([
                      LabeledExprSyntax(
                        expression: ExprSyntax(
                          StringLiteralExprSyntax(
                            openingQuote: .stringQuoteToken(),
                            segments: StringLiteralSegmentListSyntax([
                              StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(id)))
                            ]),
                            closingQuote: .stringQuoteToken()
                          )),
                        trailingComma: .commaToken()
                      ),
                      LabeledExprSyntax(
                        label: .identifier("forKey"),
                        colon: .colonToken(),
                        expression: ExprSyntax(
                          MemberAccessExprSyntax(
                            period: .periodToken(),
                            declName: DeclReferenceExprSyntax(baseName: .identifier("type"))
                          ))
                      ),
                    ]),
                    rightParen: .rightParenToken()
                  ))
              )

              TryExprSyntax(
                tryKeyword: .keyword(.try),
                expression: ExprSyntax(
                  FunctionCallExprSyntax(
                    calledExpression: ExprSyntax(
                      MemberAccessExprSyntax(
                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("value"))),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                      )),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax([
                      LabeledExprSyntax(
                        label: .identifier("to"),
                        colon: .colonToken(),
                        expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("encoder")))
                      )
                    ]),
                    rightParen: .rightParenToken()
                  ))
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
                        calledExpression: MemberAccessExprSyntax(name: .identifier("_other")),
                        leftParen: .leftParenToken(),
                        arguments: LabeledExprListSyntax([
                          .init(
                            expression: PatternExprSyntax(
                              pattern: IdentifierPatternSyntax(identifier: .identifier("value"))
                            )
                          )
                        ]),
                        rightParen: .rightParenToken()
                      )
                    )
                  ))
              ])
            )
          ) {
            TryExprSyntax(
              tryKeyword: .keyword(.try),
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

  private func genCodeArray(def: ArrayTypeDefinition, leadingTrivia: Trivia? = nil, name: String, type _: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
    let key = "elem"
    let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: def.items)
    let tname = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap)
    return VariableDeclSyntax(
      leadingTrivia: leadingTrivia,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      bindingSpecifier: .keyword(.let)
    ) {
      PatternBindingSyntax(
        pattern: PatternSyntax("type"),
        initializer: InitializerClauseSyntax(
          value: StringLiteralExprSyntax(content: tname)
        )
      )
    }
  }
}

struct ExtDef {
  let type: TypeSchema
}

struct Param: Codable {
  let type: String
  let maximum: Int
  let required: Bool
}

enum PrimaryType {
  case query
  case procedure
  case subscription
  case record
}

enum FieldType: String, Codable {
  case null
  case boolean
  case integer
  case string
  case bytes
  case cidLink = "cid-link"
  case blob
  case union
  case array
  case object
  case ref
  case permission
  case token
  case unknown
  case procedure
  case query
  case subscription
  case record
  case permissionSet = "permission-set"
}

enum AtpType {
  case concrete
  case container
  case meta
  case primary
}

struct StringFormat: Codable, RawRepresentable {
  typealias RawValue = String
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self.rawValue = rawValue
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let atIdentifier: Self = .init("at-identifier")
  static let atUri: Self = .init("at-uri")
  static let cid: Self = .init("cid")
  static let datetime: Self = .init("datetime")
  static let did: Self = .init("did")
  static let handle: Self = .init("handle")
  static let nsid: Self = .init("nsid")
  static let uri: Self = .init("uri")
  static let language: Self = .init("language")
  static let tid: Self = .init("tid")
  static let recordKey: Self = .init("record-key")
}

struct RecordSchema {
  let type: PrimaryType = .record
  let key: String
  let properties: [String: TypeSchema]
  let required: [String]?
  let nullable: [String]?
}

enum FieldTypeDefinition: Encodable, DecodableWithConfiguration, Sendable {
  typealias DecodingConfiguration = TypeSchema.DecodingConfiguration
  case token(TokenTypeDefinition)
  case null(NullTypeDefinition)
  case boolean(BooleanTypeDefinition)
  case integer(IntegerTypeDefinition)
  case blob(BlobTypeDefinition)
  case bytes(BytesTypeDefinition)
  case string(StringTypeDefinition)
  case union(UnionTypeDefinition)
  case array(ArrayTypeDefinition)
  case object(ObjectTypeDefinition)
  case ref(ReferenceTypeDefinition)
  case permission(PermissionTypeDefinition)
  case unknown(UnknownTypeDefinition)
  case cidLink(CidLinkTypeDefinition)
  case procedure(ProcedureTypeDefinition)
  case query(QueryTypeDefinition)
  case subscription(SubscriptionDefinition)
  case record(RecordDefinition)
  case permissionSet(PermissionSetTypeDefinition)
  private enum CodingKeys: String, CodingKey {
    case type
  }

  var isPrimitive: Bool {
    switch self {
    case .integer(let def):
      def.isPrimitive
    case .string(let def):
      def.isPrimitive
    case .union:
      false
    default:
      true
    }
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let type = try FieldType(rawValue: container.decode(String.self, forKey: .type)) else {
      throw DecodingError.typeMismatch(FieldTypeDefinition.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Invalid number of keys found, expected one.", underlyingError: nil))
    }
    switch type {
    case .token:
      self = try .token(TokenTypeDefinition(from: decoder))
    case .null:
      self = try .null(NullTypeDefinition(from: decoder))
    case .boolean:
      self = try .boolean(BooleanTypeDefinition(from: decoder))
    case .integer:
      self = try .integer(IntegerTypeDefinition(from: decoder))
    case .bytes:
      self = try .bytes(BytesTypeDefinition(from: decoder))
    case .blob:
      self = try .blob(BlobTypeDefinition(from: decoder))
    case .string:
      self = try .string(StringTypeDefinition(from: decoder))
    case .union:
      self = try .union(UnionTypeDefinition(from: decoder))
    case .array:
      self = try .array(ArrayTypeDefinition(from: decoder, configuration: configuration))
    case .object:
      self = try .object(ObjectTypeDefinition(from: decoder, configuration: configuration))
    case .ref:
      self = try .ref(ReferenceTypeDefinition(from: decoder))
    case .permission:
      self = try .permission(PermissionTypeDefinition(from: decoder))
    case .unknown:
      self = try .unknown(UnknownTypeDefinition(from: decoder))
    case .cidLink:
      self = try .cidLink(CidLinkTypeDefinition(from: decoder))
    case .procedure:
      self = try .procedure(ProcedureTypeDefinition(from: decoder, configuration: configuration))
    case .query:
      self = try .query(QueryTypeDefinition(from: decoder, configuration: configuration))
    case .subscription:
      self = try .subscription(SubscriptionDefinition(from: decoder, configuration: configuration))
    case .record:
      self = try .record(RecordDefinition(from: decoder, configuration: configuration))
    case .permissionSet:
      self = try .permissionSet(PermissionSetTypeDefinition(from: decoder))
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .token(let def):
      try def.encode(to: encoder)
    case .null(let def):
      try def.encode(to: encoder)
    case .boolean(let def):
      try def.encode(to: encoder)
    case .integer(let def):
      try def.encode(to: encoder)
    case .blob(let def):
      try def.encode(to: encoder)
    case .bytes(let def):
      try def.encode(to: encoder)
    case .string(let def):
      try def.encode(to: encoder)
    case .permission(let def):
      try def.encode(to: encoder)
    case .union(let def):
      try def.encode(to: encoder)
    case .array(let def):
      try def.encode(to: encoder)
    case .object(let def):
      try def.encode(to: encoder)
    case .ref(let def):
      try def.encode(to: encoder)
    case .unknown(let def):
      try def.encode(to: encoder)
    case .cidLink(let def):
      try def.encode(to: encoder)
    case .procedure(let def):
      try def.encode(to: encoder)
    case .query(let def):
      try def.encode(to: encoder)
    case .subscription(let def):
      try def.encode(to: encoder)
    case .record(let def):
      try def.encode(to: encoder)
    case .permissionSet(let def):
      try def.encode(to: encoder)
    }
  }

  func variable(name: String, type: TypeSyntax, isMutable: Bool = true) -> VariableDeclSyntax {
    VariableDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      bindingSpecifier: .keyword(isMutable ? .var : .let)
    ) {
      PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier(name.escapedSwiftKeyword)),
        typeAnnotation: TypeAnnotationSyntax(
          type: type
        )
      )
    }
  }

  var errors: [ErrorResponse]? {
    switch self {
    case .procedure(let t):
      t.errors
    case .query(let t):
      t.errors
    default:
      nil
    }
  }
}

struct TokenTypeDefinition: Codable {
  var type: FieldType { .token }
  let description: String?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
  }
}

struct NullTypeDefinition: Codable {
  var type: FieldType { .boolean }
  let description: String?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
  }
}

struct BooleanTypeDefinition: Codable {
  var type: FieldType { .boolean }
  let description: String?
  let `default`: Bool?
  let const: Bool?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case `default`
    case const
  }
}

struct IntegerTypeDefinition: Codable {
  var type: FieldType { .integer }
  let description: String?
  let minimum: Int?
  let maximum: Int?
  let `enum`: [Int]?
  let `default`: Int?
  let const: Int?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case minimum
    case maximum
    case `enum`
    case `default`
    case const
  }

  var isPrimitive: Bool {
    `enum` == nil
  }
}

struct BlobTypeDefinition: Codable {
  var type: FieldType { .blob }
  let accept: [String]?
  let maxSize: Int?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case accept
    case maxSize
  }
}

struct BytesTypeDefinition: Codable {
  var type: FieldType { .bytes }
  let minLength: Int?
  let maxLength: Int?

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case minLength
    case maxLength
  }
}

struct StringTypeDefinition: Codable {
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
}

struct ObjectTypeDefinition: Encodable, DecodableWithConfiguration {
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
}

struct ReferenceTypeDefinition: Codable {
  var type: FieldType { .ref }
  let description: String?
  let ref: String

  private enum TypedCodingKeys: String, CodingKey {
    case type
    case description
    case ref
  }
}

struct PermissionTypeDefinition: Codable {
  var type: FieldType { .permission }
  let description: String?
  let resource: String
  let inheritAud: Bool?
  let lxm: [String]?
  let action: [String]?
  let collection: [String]?
}

struct UnionTypeDefinition: Codable {
  var type: FieldType { .union }
  let description: String?
  let refs: [String]
  let closed: Bool?
}

final class ArrayTypeDefinition: Encodable, DecodableWithConfiguration, Sendable {
  var type: FieldType { .array }

  let items: FieldTypeDefinition
  let description: String?
  let minLength: Int?
  let maxLength: Int?

  private enum CodingKeys: String, CodingKey {
    case type
    case description
    case items
    case minLength
    case maxLength
  }

  init(from decoder: Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    items = try container.decode(FieldTypeDefinition.self, forKey: .items, configuration: configuration)
    minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
    maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(items, forKey: .items)
    try container.encodeIfPresent(maxLength, forKey: .maxLength)
    try container.encodeIfPresent(minLength, forKey: .minLength)
  }
}

struct PermissionSetTypeDefinition: Codable {
  let type: FieldType
  let description: String?
  let title: String?
  let titleLang: [String: String]?
  let detail: String?
  let detailLang: [String: String]?
  let permissions: [PermissionTypeDefinition]

  private enum CodingKeys: String, CodingKey {
    case type
    case description
    case title
    case titleLang = "title:lang"
    case detail
    case detailLang = "detail:lang"
    case permissions
  }
}

struct UnknownTypeDefinition: Codable {
  var type: FieldType { .unknown }
}

struct CidLinkTypeDefinition: Codable {
  var type: FieldType { .cidLink }
}

enum EncodingType: String, Codable {
  case cbor = "application/cbor"
  case json = "application/json"
  case jsonl = "application/jsonl"
  case car = "application/vnd.ipld.car"
  case text = "text/plain"
  case mp4 = "video/mp4"
  case any = "*/*"

  init(from decoder: Decoder) throws {
    let rawValue = try String(from: decoder)

    guard let value = EncodingType(rawValue: rawValue) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unexpected mimetype: \(rawValue.debugDescription)"))
    }
    self = value
  }

  func encode(to encoder: Encoder) throws {
    try rawValue.encode(to: encoder)
  }
}

struct OutputType: Encodable, DecodableWithConfiguration {
  let encoding: EncodingType
  let schema: TypeSchema?
  let description: String?

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    encoding = try container.decode(EncodingType.self, forKey: .encoding)
    schema = try container.decodeIfPresent(TypeSchema.self, forKey: .schema, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
  }
}

struct MessageType: Encodable, DecodableWithConfiguration {
  let description: String?
  let schema: TypeSchema

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    schema = try container.decode(TypeSchema.self, forKey: .schema, configuration: configuration)
  }
}

typealias InputType = OutputType

struct Parameters: Encodable, DecodableWithConfiguration {
  var type: String {
    "params"
  }

  let required: [String]?
  let properties: [String: FieldTypeDefinition]
  var sortedProperties: [(String, FieldTypeDefinition)] {
    properties.keys.sorted().compactMap {
      guard let property = properties[$0] else { return nil }
      return ($0, property)
    }
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    required = try container.decodeIfPresent([String].self, forKey: .required)
    var properties = [String: FieldTypeDefinition]()
    let nestedContainer = try container.nestedContainer(keyedBy: AnyCodingKeys.self, forKey: .properties)
    for key in nestedContainer.allKeys {
      properties[key.stringValue] = try nestedContainer.decode(FieldTypeDefinition.self, forKey: key, configuration: configuration)
    }
    self.properties = properties
  }
}

protocol HTTPAPITypeDefinition: Encodable, DecodableWithConfiguration {
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
  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol?
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

  func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol? {
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
      return nil
    }
  }
}

struct ProcedureTypeDefinition: HTTPAPITypeDefinition {
  var type: FieldType { .procedure }
  let parameters: Parameters?
  let output: OutputType?
  let input: InputType?
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
    input = try container.decodeIfPresent(InputType.self, forKey: .input, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    errors = try container.decodeIfPresent([ErrorResponse].self, forKey: .errors)
  }
}

struct QueryTypeDefinition: HTTPAPITypeDefinition {
  var type: FieldType { .query }
  let parameters: Parameters?
  let output: OutputType?
  let input: InputType?
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
    input = try container.decodeIfPresent(InputType.self, forKey: .input, configuration: configuration)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    errors = try container.decodeIfPresent([ErrorResponse].self, forKey: .errors)
  }
}

struct SubscriptionDefinition: Encodable, DecodableWithConfiguration {
  var type: FieldType {
    .subscription
  }

  let parameters: Parameters?
  let message: MessageType?

  private enum CodingKeys: String, CodingKey {
    case type
    case parameters
    case message
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    parameters = try container.decodeIfPresent(Parameters.self, forKey: .parameters, configuration: configuration)
    message = try container.decodeIfPresent(MessageType.self, forKey: .message, configuration: configuration)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(parameters, forKey: .parameters)
    try container.encodeIfPresent(message, forKey: .message)
  }
}

struct RecordDefinition: Encodable, DecodableWithConfiguration {
  typealias DecodingConfiguration = TypeSchema.DecodingConfiguration

  var type: FieldType {
    .record
  }

  let key: String
  let record: ObjectTypeDefinition

  private enum CodingKeys: String, CodingKey {
    case type
    case key
    case record
  }

  init(from decoder: any Decoder, configuration: TypeSchema.DecodingConfiguration) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(String.self, forKey: .key)
    record = try container.decode(ObjectTypeDefinition.self, forKey: .record, configuration: configuration)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(key, forKey: .key)
    try container.encode(record, forKey: .record)
  }
}

struct ErrorResponse: Codable, Equatable, Hashable {
  let name: String
  let description: String?

  func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }

  static func == (lhs: ErrorResponse, rhs: ErrorResponse) -> Bool {
    lhs.name == rhs.name
  }
}

extension ErrorResponse: Comparable {
  static func < (lhs: ErrorResponse, rhs: ErrorResponse) -> Bool {
    lhs.name < rhs.name
  }
}

func decodableInitializerDeclSyntax(
  leadingTrivia: Trivia? = nil,
  @CodeBlockItemListBuilder bodyBuilder: () throws -> CodeBlockItemListSyntax?
) rethrows -> InitializerDeclSyntax {
  try InitializerDeclSyntax(
    leadingTrivia: leadingTrivia,
    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
    signature: FunctionSignatureSyntax(
      parameterClause: FunctionParameterClauseSyntax {
        FunctionParameterSyntax(
          firstName: .identifier("from"),
          secondName: .identifier("decoder"),
          type: SomeOrAnyTypeSyntax(
            someOrAnySpecifier: .keyword(.any),
            constraint: IdentifierTypeSyntax(name: .identifier("Decoder"))
          )
        )

      },
      effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
    ),
    bodyBuilder: bodyBuilder
  )
}

func encodableFunctionDeclSyntax(leadingTrivia: Trivia? = nil, @CodeBlockItemListBuilder bodyBuilder: () throws -> CodeBlockItemListSyntax?) rethrows -> FunctionDeclSyntax {
  try FunctionDeclSyntax(
    leadingTrivia: leadingTrivia,
    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
    name: .identifier("encode"),
    signature: FunctionSignatureSyntax(
      parameterClause: FunctionParameterClauseSyntax {
        FunctionParameterSyntax(
          firstName: .identifier("to"),
          secondName: .identifier("encoder"),
          type: SomeOrAnyTypeSyntax(
            someOrAnySpecifier: .keyword(.any),
            constraint: IdentifierTypeSyntax(name: .identifier("Encoder"))
          )
        )
      },
      effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)))
    ), bodyBuilder: bodyBuilder)
}
