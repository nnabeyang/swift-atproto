import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

#if os(macOS) || os(Linux)
  import SourceControl
#endif

public func main(outdir: String, path: String, generate: GenerateOption) async throws {
  let url = URL(filePath: path)

  let fileURLs = collectJSONFileURLs(at: url)
  let schemasMap = try await decodeSchemasByPrefix(from: fileURLs, baseURL: url)
  let defMap = Lex.buildExtDefMap(schemasMap: schemasMap)
  let outdirBaseURL = URL(filePath: outdir)
  try await writeSchemaCode(for: schemasMap, with: defMap, to: outdirBaseURL, generate: generate)
}

func collectJSONFileURLs(at baseURL: URL) -> [URL] {
  var fileURLs = [URL]()
  if let enumerator = FileManager.default.enumerator(at: baseURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
    for case let fileUrl as URL in enumerator {
      do {
        let fileAttributes = try fileUrl.resourceValues(forKeys: [.isRegularFileKey])
        if fileAttributes.isRegularFile!, fileUrl.pathExtension == "json" {
          fileURLs.append(fileUrl)
        }
      } catch {
        print(error, fileUrl)
      }
    }
  }
  return fileURLs
}

func decodeSchemasByPrefix(from fileURLs: [URL], baseURL: URL) async throws -> [String: [Schema]] {
  let decoder = JSONDecoder()
  return try await withThrowingTaskGroup(of: Schema.self) { group in
    for fileURL in fileURLs {
      group.addTask {
        let data = try Data(contentsOf: fileURL)
        let prefix = fileURL.prefix(baseURL: baseURL)
        return try decoder.decode(Schema.self, from: data, configuration: prefix)
      }
    }
    var schemasMap = [String: [Schema]]()
    for try await schema in group {
      schemasMap[schema.prefix, default: []].append(schema)
    }
    return schemasMap
  }
}

func createOutputDirectory(for prefix: String, baseURL: URL) throws {
  let filePrefix = prefix.split(separator: ".").joined()
  let outdirURL = baseURL.appending(path: filePrefix)

  if FileManager.default.fileExists(atPath: outdirURL.path) {
    try FileManager.default.removeItem(at: outdirURL)
  }
  try FileManager.default.createDirectory(
    at: outdirURL,
    withIntermediateDirectories: true
  )
}

func writeSchemaCode(
  for schemasMap: [String: [Schema]],
  with defMap: ExtDefMap,
  to baseURL: URL,
  generate: GenerateOption
) async throws {
  let schemasArray = schemasMap.sorted { $0.key < $1.key }
  var srcs = try await withThrowingTaskGroup(of: (String?, Int).self) { group in
    let src = Lex.genUnknownRecord(for: schemasMap)
    let recordURL = baseURL.appending(path: "UnknownATPValue.swift")
    try src.write(to: recordURL, atomically: true, encoding: .utf8)
    let serverSrc: String
    if generate.contains(.server) {
      serverSrc = Lex.genXRPCAPIProtocolFile(for: schemasMap, defMap: defMap)
    } else {
      serverSrc = ""
    }
    let serverURL = baseURL.appending(path: "XRPCAPIProtocol.swift")
    try serverSrc.write(to: serverURL, atomically: true, encoding: .utf8)
    for (i, (prefix, schemas)) in schemasArray.enumerated() {
      group.addTask {
        let baseSrc = Lex.baseFile(prefix: prefix)
        let srcs = try await withThrowingTaskGroup(of: (String?, Int).self) { innerGroup in
          for (j, schema) in schemas.sorted(by: { $0.id < $1.id }).enumerated() {
            innerGroup.addTask {
              let src: String? = Lex.genCode(for: schema, defMap: defMap, generate: generate)
              return (src, j)
            }
          }
          var srcs: [String?] = Array(repeating: nil, count: schemas.count)
          for try await (src, j) in innerGroup {
            srcs[j] = src
          }
          return srcs
        }
        return (baseSrc + srcs.compactMap({ $0 }).joined(separator: "\n"), i)
      }
    }
    var srcs: [String?] = Array(repeating: nil, count: schemasMap.count)
    for try await (src, i) in group {
      srcs[i] = src
    }
    return srcs
  }
  srcs.insert(
    SourceFileSyntax(leadingTrivia: Lex.fileHeader) {
      ImportDeclSyntax(
        path: [ImportPathComponentSyntax(name: "Foundation")]
      )
      ImportDeclSyntax(
        path: [ImportPathComponentSyntax(name: "SwiftAtproto")],
        trailingTrivia: generate.contains(.server) ? nil : .newlines(2)
      )
      if generate.contains(.server) {
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
      }
    }.formatted().description, at: 0)

  let clientSrc = srcs.compactMap({ $0 }).joined(separator: "\n")
  let clientURL = baseURL.appending(path: "XRPCAPIClient.swift")
  try clientSrc.write(to: clientURL, atomically: true, encoding: .utf8)
}

extension URL {
  fileprivate func prefix(baseURL: URL) -> String {
    precondition(path.hasPrefix(baseURL.path))
    let relativeCount = pathComponents.count - baseURL.pathComponents.count
    let url = relativeCount >= 4 ? deletingLastPathComponent() : self
    return url.deletingLastPathComponent().path.dropFirst(baseURL.path.count + 1).replacingOccurrences(of: "/", with: ".")
  }
}

enum Lex {
  static var fileHeader: Trivia {
    Trivia(pieces: [
      .lineComment("//"),
      .newlines(1),
      .lineComment("// DO NOT EDIT"),
      .newlines(1),
      .lineComment("//"),
      .newlines(1),
      .lineComment("// Generated by swift-atproto"),
      .newlines(1),
      .lineComment("//"),
      .newlines(2),
    ])
  }

  static func baseFile(prefix: String) -> String {
    let src = SourceFileSyntax(
      statementsBuilder: {
        EnumDeclSyntax(
          modifiers: [
            DeclModifierSyntax(name: .keyword(.public))
          ],
          name: .identifier(Lex.structNameFor(prefix: prefix))
        ) {}
      },
      trailingTrivia: .newline)
    return src.formatted().description
  }

  static func genCode(for schema: Schema, defMap: ExtDefMap, generate: GenerateOption) -> String? {
    let prefix = schema.prefix
    let structName = Lex.structNameFor(prefix: prefix)
    let allTypes = schema.allTypes(prefix: prefix).sorted(by: {
      $0.key.localizedStandardCompare($1.key) == .orderedAscending
    })
    let recordTypes = allTypes.filter(\.value.isRecord)
    let otherTypes = allTypes.filter { !$0.value.isRecord }
    let methods = allTypes.filter { !$0.value.isRecord && $0.value.isMethod }
    let enumExtensionIsNeeded = !otherTypes.isEmpty || !methods.isEmpty
    if otherTypes.isEmpty && methods.isEmpty && recordTypes.isEmpty {
      return nil
    }
    let src = SourceFileSyntax(
      statementsBuilder: {
        if enumExtensionIsNeeded {
          ExtensionDeclSyntax(leadingTrivia: .newline, extendedType: TypeSyntax(stringLiteral: structName)) {
            for (i, (name, ot)) in otherTypes.enumerated() {
              ot.lex(
                leadingTrivia: i == 0 ? nil : .newlines(2),
                name: name,
                type: (ot.defName.isEmpty || ot.defName == "main") ? ot.id : "\(ot.id)#\(ot.defName)",
                defMap: defMap,
                generate: generate
              )
            }
            for method in methods {
              TypeAliasDeclSyntax(
                leadingTrivia: .newlines(2),
                attributes: [
                  AttributeListSyntax.Element(
                    AttributeSyntax(
                      atSign: .atSignToken(),
                      attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("available"))),
                      leftParen: .leftParenToken(),
                      arguments: AttributeSyntax.Arguments(
                        AvailabilityArgumentListSyntax {
                          AvailabilityArgumentSyntax(
                            argument: AvailabilityArgumentSyntax.Argument(.binaryOperator("*"))
                          )
                          AvailabilityArgumentSyntax(
                            argument: AvailabilityArgumentSyntax.Argument(.keyword(.deprecated))
                          )
                          AvailabilityArgumentSyntax(
                            argument: AvailabilityArgumentSyntax.Argument(
                              AvailabilityLabeledArgumentSyntax(
                                label: .keyword(.message),
                                colon: .colonToken(),
                                value: AvailabilityLabeledArgumentSyntax.Value(
                                  SimpleStringLiteralExprSyntax(
                                    openingQuote: .stringQuoteToken(),
                                    segments: SimpleStringLiteralSegmentListSyntax([
                                      StringSegmentSyntax(content: .stringSegment("Use `\(method.key).Error` instead."))
                                    ]),
                                    closingQuote: .stringQuoteToken()
                                  ))
                              )))
                        }),
                      rightParen: .rightParenToken()
                    )
                  )
                ],
                modifiers: [DeclModifierSyntax(name: .keyword(.public, leadingTrivia: .newline))],
                name: .identifier("\(method.key)_Error"),
                initializer: TypeInitializerClauseSyntax(
                  equal: .equalToken(),
                  value: MemberTypeSyntax(parts: [.identifier(method.key), .identifier("Error")])
                )
              )
            }
          }
        }
        if generate.contains(.client) && !methods.isEmpty {
          ExtensionDeclSyntax(extendedType: TypeSyntax(stringLiteral: "XRPCClientProtocol")) {
            for method in methods {
              writeMethod(
                leadingTrivia: otherTypes.isEmpty ? nil : .newlines(2),
                typeName: Self.nameFromId(id: method.value.id, prefix: method.value.prefix),
                typeSchema: method.value,
                defMap: defMap,
                prefix: structNameFor(prefix: prefix)
              )
            }
          }
        }
        for (name, ot) in recordTypes {
          ot.lex(
            leadingTrivia: .newlines(2),
            name: name,
            type: (ot.defName.isEmpty || ot.defName == "main") ? ot.id : "\(ot.id)#\(ot.defName)",
            defMap: defMap,
            generate: generate
          )
        }
      },
      trailingTrivia: .newline)
    return src.formatted().description
  }

  static func writeMethod(leadingTrivia: Trivia? = nil, typeName: String, typeSchema ts: TypeSchema, defMap: ExtDefMap, prefix: String) -> DeclSyntaxProtocol {
    switch ts.type {
    case .procedure(let def as any HTTPAPITypeDefinition), .query(let def as any HTTPAPITypeDefinition):
      ts.writeRPC(leadingTrivia: nil, def: def, typeName: typeName, defMap: defMap, prefix: prefix)
    default:
      fatalError()
    }
  }

  static func genUnknownRecord(for schemasMap: [String: [Schema]]) -> String {
    var recordTypes = [(key: String, value: TypeSchema)]()
    for schemas in schemasMap {
      for schema in schemas.value {
        let prefix = schema.prefix
        recordTypes.append(contentsOf: schema.allTypes(prefix: prefix).filter(\.value.isRecord))
      }
    }
    let src = SourceFileSyntax(leadingTrivia: fileHeader) {
      ImportDeclSyntax(
        path: [ImportPathComponentSyntax(name: "SwiftAtproto")],
        trailingTrivia: .newlines(2)
      )
      EnumDeclSyntax(
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        name: .identifier("UnknownATPValue"),
        inheritanceClause: InheritanceClauseSyntax(typeNames: ["UnknownATPValueProtocol"])
      ) {
        EnumCaseDeclSyntax(leadingTrivia: [.newlines(1), .spaces(2)]) {
          EnumCaseElementSyntax(
            name: .identifier("record"),
            parameterClause: EnumCaseParameterClauseSyntax(
              parameters: [
                EnumCaseParameterSyntax(
                  type: SomeOrAnyTypeSyntax(
                    someOrAnySpecifier: .keyword(.any),
                    constraint: TypeSyntax(IdentifierTypeSyntax(name: .identifier("ATProtoRecord")))
                  )
                )
              ]
            )
          )
        }
        EnumCaseDeclSyntax(leadingTrivia: [.newlines(1), .spaces(2)]) {
          EnumCaseElementSyntax(
            name: .identifier("any"),
            parameterClause: EnumCaseParameterClauseSyntax(
              parameters: [
                EnumCaseParameterSyntax(
                  type: SomeOrAnyTypeSyntax(
                    someOrAnySpecifier: .keyword(.any),
                    constraint: CompositionTypeSyntax(
                      elements: [
                        CompositionTypeElementSyntax(
                          type: IdentifierTypeSyntax(name: .identifier("Codable")),
                          ampersand: .binaryOperator("&")
                        ),
                        CompositionTypeElementSyntax(
                          type: IdentifierTypeSyntax(name: .identifier("Hashable")),
                          ampersand: .binaryOperator("&")
                        ),
                        CompositionTypeElementSyntax(type: IdentifierTypeSyntax(name: .identifier("Sendable"))),
                      ]))
                )
              ]
            )
          )
        }
        VariableDeclSyntax(
          leadingTrivia: [.newlines(2), .spaces(2)],
          modifiers: [
            DeclModifierSyntax(name: .keyword(.public)),
            DeclModifierSyntax(name: .keyword(.static)),
          ],
          bindingSpecifier: .keyword(.let),
          bindings: [
            PatternBindingSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("allTypes")),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: DictionaryTypeSyntax(
                  leftSquare: .leftSquareToken(),
                  key: IdentifierTypeSyntax(name: .identifier("String")),
                  colon: .colonToken(),
                  value: SomeOrAnyTypeSyntax(
                    someOrAnySpecifier: .keyword(.any),
                    constraint: MetatypeTypeSyntax(
                      baseType: IdentifierTypeSyntax(name: .identifier("ATProtoRecord")),
                      period: .periodToken(),
                      metatypeSpecifier: .keyword(.Type)
                    )
                  ),
                  rightSquare: .rightSquareToken()
                )
              ),
              initializer: InitializerClauseSyntax(
                equal: .equalToken(),
                value: DictionaryExprSyntax(rightSquare: .rightSquareToken(leadingTrivia: [.newlines(1), .spaces(2)])) {
                  for (name, recordType) in recordTypes.sorted(by: { $0.value.id < $1.value.id }) {
                    DictionaryElementSyntax(
                      key: StringLiteralExprSyntax(openingQuote: .stringQuoteToken(leadingTrivia: [.newlines(1), .spaces(4)]), content: recordType.id),
                      colon: .colonToken(),
                      value: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("\(Lex.structNameFor(prefix: recordType.prefix))_\(name)")),
                        period: .periodToken(),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ),
                      trailingComma: .commaToken()
                    )
                  }
                }
              )
            )
          ]
        )
        VariableDeclSyntax(
          leadingTrivia: [.newlines(2), .spaces(2)],
          modifiers: [
            DeclModifierSyntax(name: .keyword(.public))
          ],
          bindingSpecifier: .keyword(.var),
          bindings: [
            PatternBindingSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("type")),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String")))
              ),
              accessorBlock: AccessorBlockSyntax(
                leftBrace: .leftBraceToken(),
                accessors: .getter(
                  CodeBlockItemListSyntax {
                    ExpressionStmtSyntax(
                      expression: SwitchExprSyntax(
                        leadingTrivia: [.newlines(1), .spaces(4)],
                        subject: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ) {
                        SwitchCaseSyntax(
                          label: SwitchCaseSyntax.Label(
                            SwitchCaseLabelSyntax(
                              leadingTrivia: [.newlines(1), .spaces(4)]) {
                                SwitchCaseItemSyntax(
                                  pattern: ExpressionPatternSyntax(
                                    expression: FunctionCallExprSyntax(
                                      callee: MemberAccessExprSyntax(
                                        period: .periodToken(),
                                        declName: DeclReferenceExprSyntax(baseName: .identifier("record"))
                                      )
                                    ) {
                                      LabeledExprSyntax(
                                        expression: PatternExprSyntax(
                                          pattern: ValueBindingPatternSyntax(
                                            bindingSpecifier: .keyword(.let),
                                            pattern: IdentifierPatternSyntax(identifier: .identifier("record"))
                                          )))
                                    }
                                  ))
                              }
                          )
                        ) {
                          ReturnStmtSyntax(
                            leadingTrivia: [.newlines(1), .spaces(6)],
                            expression: MemberAccessExprSyntax(
                              base: FunctionCallExprSyntax(
                                callee: MemberAccessExprSyntax(
                                  base: DeclReferenceExprSyntax(baseName: .identifier("Swift")),
                                  period: .periodToken(),
                                  declName: DeclReferenceExprSyntax(baseName: .identifier("type"))
                                )
                              ) {
                                LabeledExprSyntax(
                                  label: .identifier("of"),
                                  colon: .colonToken(),
                                  expression: DeclReferenceExprSyntax(baseName: .identifier("record"))
                                )
                              },
                              period: .periodToken(),
                              declName: DeclReferenceExprSyntax(baseName: .identifier("nsId"))
                            )
                          )
                        }
                        SwitchCaseSyntax(
                          label: SwitchCaseSyntax.Label(
                            SwitchCaseLabelSyntax(
                              leadingTrivia: [.newlines(1), .spaces(4)],
                              caseItems: [
                                SwitchCaseItemSyntax(
                                  pattern: ExpressionPatternSyntax(
                                    expression: MemberAccessExprSyntax(
                                      period: .periodToken(),
                                      declName: DeclReferenceExprSyntax(baseName: .identifier("any"))
                                    )))
                              ],
                              colon: .colonToken()
                            ))
                        ) {
                          ReturnStmtSyntax(
                            leadingTrivia: [.newlines(1), .spaces(6)],
                            expression: NilLiteralExprSyntax()
                          )
                        }
                      }
                      .with(
                        \.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)])
                      ))
                  }),
                rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(2)])
              )
            )
          ]
        )
        VariableDeclSyntax(
          leadingTrivia: [.newlines(2), .spaces(2)],
          modifiers: [
            DeclModifierSyntax(name: .keyword(.public))
          ],
          bindingSpecifier: .keyword(.var),
          bindings: [
            PatternBindingSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("val")),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: CompositionTypeSyntax(
                  elements: [
                    CompositionTypeElementSyntax(
                      type: SomeOrAnyTypeSyntax(
                        someOrAnySpecifier: .keyword(.any),
                        constraint: IdentifierTypeSyntax(name: .identifier("Codable"))
                      ),
                      ampersand: .binaryOperator("&")
                    ),
                    CompositionTypeElementSyntax(
                      type: IdentifierTypeSyntax(name: .identifier("Hashable")),
                      ampersand: .binaryOperator("&")
                    ),
                    CompositionTypeElementSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Sendable")))),
                  ])
              ),
              accessorBlock: AccessorBlockSyntax(
                leftBrace: .leftBraceToken(),
                accessors: .getter(
                  CodeBlockItemListSyntax {
                    ExpressionStmtSyntax(
                      expression: SwitchExprSyntax(
                        leadingTrivia: [.newlines(1), .spaces(4)],
                        subject: DeclReferenceExprSyntax(baseName: .keyword(.self))
                      ) {
                        SwitchCaseSyntax(
                          label: SwitchCaseSyntax.Label(
                            SwitchCaseLabelSyntax(
                              leadingTrivia: [.newlines(1), .spaces(4)]) {
                                SwitchCaseItemSyntax(
                                  pattern: ExpressionPatternSyntax(
                                    expression: FunctionCallExprSyntax(
                                      callee: MemberAccessExprSyntax(
                                        period: .periodToken(),
                                        declName: DeclReferenceExprSyntax(baseName: .identifier("record"))
                                      )
                                    ) {
                                      LabeledExprSyntax(
                                        expression: PatternExprSyntax(
                                          pattern: ValueBindingPatternSyntax(
                                            bindingSpecifier: .keyword(.let),
                                            pattern: IdentifierPatternSyntax(identifier: .identifier("record"))
                                          )))
                                    }
                                  ))
                              }
                          )
                        ) {
                          DeclReferenceExprSyntax(baseName: .identifier("record", leadingTrivia: [.newlines(1), .spaces(6)]))
                        }
                        SwitchCaseSyntax(
                          label: SwitchCaseSyntax.Label(
                            SwitchCaseLabelSyntax(
                              leadingTrivia: [.newlines(1), .spaces(4)]) {
                                SwitchCaseItemSyntax(
                                  pattern: ExpressionPatternSyntax(
                                    expression: FunctionCallExprSyntax(
                                      callee: MemberAccessExprSyntax(
                                        period: .periodToken(),
                                        declName: DeclReferenceExprSyntax(baseName: .identifier("any"))
                                      )
                                    ) {
                                      LabeledExprSyntax(
                                        expression: PatternExprSyntax(
                                          pattern: ValueBindingPatternSyntax(
                                            bindingSpecifier: .keyword(.let),
                                            pattern: IdentifierPatternSyntax(identifier: .identifier("object"))
                                          )))
                                    }
                                  ))
                              }
                          )
                        ) {
                          CodeBlockItemSyntax(
                            item: CodeBlockItemSyntax.Item(
                              DeclReferenceExprSyntax(baseName: .identifier("object", leadingTrivia: [.newlines(1), .spaces(6)]))
                            ))
                        }
                      }
                      .with(\.rightBrace, .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(4)]))
                    )
                  }),
                rightBrace: .rightBraceToken(leadingTrivia: [.newlines(1), .spaces(2)])
              )
            )
          ]
        )
      }
      TypeAliasDeclSyntax(
        leadingTrivia: .newlines(2),
        attributes: [
          AttributeListSyntax.Element(
            AttributeSyntax(
              atSign: .atSignToken(),
              attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("available"))),
              leftParen: .leftParenToken(),
              arguments: AttributeSyntax.Arguments(
                AvailabilityArgumentListSyntax([
                  AvailabilityArgumentSyntax(
                    argument: AvailabilityArgumentSyntax.Argument(.binaryOperator("*")),
                    trailingComma: .commaToken()
                  ),
                  AvailabilityArgumentSyntax(
                    argument: AvailabilityArgumentSyntax.Argument(.keyword(.deprecated)),
                    trailingComma: .commaToken()
                  ),
                  AvailabilityArgumentSyntax(
                    argument: AvailabilityArgumentSyntax.Argument(
                      AvailabilityLabeledArgumentSyntax(
                        label: .keyword(.message),
                        colon: .colonToken(),
                        value: AvailabilityLabeledArgumentSyntax.Value(
                          SimpleStringLiteralExprSyntax(
                            openingQuote: .stringQuoteToken(),
                            segments: SimpleStringLiteralSegmentListSyntax([
                              StringSegmentSyntax(content: .stringSegment("Use `UnknownATPValue` instead."))
                            ]),
                            closingQuote: .stringQuoteToken()
                          ))
                      ))),
                ])),
              rightParen: .rightParenToken()
            )
          )
        ],
        modifiers: [DeclModifierSyntax(name: .keyword(.public, leadingTrivia: .newline))],
        name: .identifier("LexiconTypeDecoder"),
        initializer: TypeInitializerClauseSyntax(
          equal: .equalToken(),
          value: IdentifierTypeSyntax(name: .identifier("UnknownATPValue"))
        )
      )
    }
    .with(\.trailingTrivia, .newline)
    return src.formatted().description
  }

  static func buildExtDefMap(schemasMap: [String: [Schema]]) -> ExtDefMap {
    var out = ExtDefMap()
    for (_, schemas) in schemasMap {
      for schema in schemas {
        for (defName, def) in schema.defs {
          let key = {
            if defName == "main" {
              return schema.id
            }
            return "\(schema.id)#\(defName)"
          }()
          out[key] = ExtDef(type: def)
        }
      }
    }
    return out
  }

  static func nameFromId(id: String, prefix: String) -> String {
    id.trim(prefix: prefix).split(separator: ".").map {
      $0.titleCased()
    }.joined()
  }

  static func structNameFor(prefix: String) -> String {
    "\(prefix.split(separator: ".").joined())types"
  }

  static func caseNameFromId(id: String, prefix: String) -> String {
    id.trim(prefix: "\(prefix).").components(separatedBy: CharacterSet(charactersIn: ".#")).enumerated().map {
      $0 == 0 ? $1 : $1.titleCased()
    }.joined()
  }
}

extension String {
  func trim(prefix: String) -> String {
    guard hasPrefix(prefix) else { return self }
    return String(dropFirst(prefix.count))
  }

  func titleCased() -> String {
    var prev = Character(" ")
    return String(
      map {
        if prev.isWhitespace {
          prev = $0
          return Character($0.uppercased())
        }
        prev = $0
        return $0
      })
  }

  func camelCased() -> String {
    guard !isEmpty else { return "" }
    let words = components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    if words.isEmpty { return self }
    let first = words.first!.lowercased()
    let rest = words.dropFirst().map(\.capitalized)
    return ([first] + rest).joined()
  }

  var escapedSwiftKeyword: String {
    isNeedEscapingKeyword(self) ? "`\(self)`" : self
  }
}

extension Substring {
  func titleCased() -> String {
    var prev = Character(" ")
    return String(
      map {
        if prev.isWhitespace {
          prev = $0
          return Character($0.uppercased())
        }
        prev = $0
        return $0
      })
  }
}
