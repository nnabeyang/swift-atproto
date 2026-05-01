import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

#if os(macOS) || os(Linux)
  import SourceControl
#endif

public func main(outdir outdirBaseURL: URL, path: String, generate: GenerateOption) async throws {
  let url = URL(filePath: path)

  let fileURLs = collectJSONFileURLs(at: url)
  let schemasMap = try await decodeSchemasByPrefix(from: fileURLs, baseURL: url)
  let defMap = Lex.buildExtDefMap(schemasMap: schemasMap)
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
  let (blocks, methods, requirements) = try await withThrowingTaskGroup(of: (DeclSyntax, MemberBlockItemListSyntax, MemberBlockItemListSyntax, Int).self) { group in
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
        let (types, methods, requirements) = try await withThrowingTaskGroup(of: (MemberBlockItemListSyntax, MemberBlockItemListSyntax, MemberBlockItemListSyntax, Int).self) { innerGroup in
          for (j, schema) in schemas.sorted(by: { $0.id < $1.id }).enumerated() {
            innerGroup.addTask {
              let prefix = schema.prefix
              let allTypes = schema.allTypes(prefix: prefix).sorted(by: {
                $0.key.localizedStandardCompare($1.key) == .orderedAscending
              })
              let methodTypes = allTypes.filter { $0.value.isMethod }
              let types = Lex.genTypes(prefix: prefix, otherTypes: allTypes, methods: methodTypes, defMap: defMap, generate: generate)
              let methods = Lex.genMethods(leadingTrivia: allTypes.isEmpty ? nil : .spaces(2), prefix: prefix, methods: methodTypes, defMap: defMap, generate: generate, protocolRequirement: false)
              let requirements = Lex.genMethods(leadingTrivia: allTypes.isEmpty ? nil : .spaces(2), prefix: prefix, methods: methodTypes, defMap: defMap, generate: generate, protocolRequirement: true)
              return (types, methods, requirements, j)
            }
          }
          var types: [MemberBlockItemListSyntax] = Array(repeating: .empty, count: schemas.count)
          var methods: [MemberBlockItemListSyntax] = Array(repeating: .empty, count: schemas.count)
          var requirements: [MemberBlockItemListSyntax] = Array(repeating: .empty, count: schemas.count)
          for try await (type, method, requrement, j) in innerGroup {
            types[j] = type
            methods[j] = method
            requirements[j] = requrement
          }
          return (combine(types), combine(methods), combine(requirements))
        }
        return (
          DeclSyntax(
            ExtensionDeclSyntax(
              extendedType: TypeSyntax(MemberTypeSyntax(parts: Lex.enumIdentifiersFor(prefix: prefix)))
            ) { types }),
          methods,
          requirements,
          i
        )
      }
    }

    var blocks: [CodeBlockItemListSyntax] = Array(repeating: .empty, count: schemasMap.count)
    var methods: [MemberBlockItemListSyntax] = Array(repeating: .empty, count: schemasMap.count)
    var requirements: [MemberBlockItemListSyntax] = Array(repeating: .empty, count: schemasMap.count)
    for try await (decl, method, requirement, i) in group {
      blocks[i] = CodeBlockItemListSyntax { decl }
      methods[i] = method
      requirements[i] = requirement
    }
    return (combine(blocks), combine(methods), combine(requirements))
  }
  let prefixes = schemasArray.map(\.0)
  let clientSrc: String = SourceFileSyntax(leadingTrivia: Lex.fileHeader) {
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
    for node in EnumDeclSyntaxNode.buildTree(from: prefixes) {
      node.generateEnums()
    }
    blocks
    if !methods.isEmpty {
      ProtocolDeclSyntax(
        leadingTrivia: nil,
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        name: .identifier("XRPCClientProtocol"),
        inheritanceClause: InheritanceClauseSyntax(typeNames: ["_XRPCClientProtocol"])
      ) {
        requirements
      }
      ExtensionDeclSyntax(extendedType: TypeSyntax(stringLiteral: "XRPCClientProtocol")) {
        methods
      }
    }
  }.formatted().description
  let clientURL = baseURL.appending(path: "XRPCAPIClient.swift")
  try clientSrc.write(to: clientURL, atomically: true, encoding: .utf8)
}

class EnumDeclSyntaxNode {
  let name: String
  var children: [String: EnumDeclSyntaxNode] = [:]

  init(name: String) {
    self.name = name
  }

  func generateEnums() -> EnumDeclSyntax {
    EnumDeclSyntax(
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .identifier(name)
    ) {
      for childKey in children.keys.sorted() {
        children[childKey]!.generateEnums()
      }
    }
  }

  static func buildTree(from strings: [String]) -> [EnumDeclSyntaxNode] {
    var roots: [String: EnumDeclSyntaxNode] = [:]

    for s in strings {
      let parts = s.components(separatedBy: ".")
      guard let firstPart = parts.first else { continue }

      if roots[firstPart] == nil {
        roots[firstPart] = EnumDeclSyntaxNode(name: firstPart.capitalized)
      }

      var current = roots[firstPart]!
      for part in parts.dropFirst() {
        if current.children[part] == nil {
          current.children[part] = EnumDeclSyntaxNode(name: part.capitalized)
        }
        current = current.children[part]!
      }
    }
    return roots.values.sorted { $0.name < $1.name }
  }
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

  @MemberBlockItemListBuilder
  static func genTypes(prefix: String, otherTypes: [[String: TypeSchema].Element], methods: [[String: TypeSchema].Element], defMap: ExtDefMap, generate: GenerateOption) -> MemberBlockItemListSyntax {
    for (i, (name, ot)) in otherTypes.enumerated() {
      ot.lex(
        leadingTrivia: i == 0 ? nil : .newlines(2),
        name: name,
        type: (ot.defName.isEmpty || ot.defName == "main") ? ot.id : "\(ot.id)#\(ot.defName)",
        defMap: defMap,
        generate: generate
      )
    }
  }

  @MemberBlockItemListBuilder
  static func genMethods(leadingTrivia: Trivia? = nil, prefix: String, methods: [[String: TypeSchema].Element], defMap: ExtDefMap, generate: GenerateOption, protocolRequirement: Bool) -> MemberBlockItemListSyntax {
    if generate.contains(.client) {
      for (i, method) in methods.enumerated() {
        writeMethod(
          leadingTrivia: i == 0 ? leadingTrivia : nil,
          typeName: Self.nameFromId(id: method.value.id, prefix: method.value.prefix),
          typeSchema: method.value,
          defMap: defMap,
          prefix: structNameFor(prefix: prefix),
          protocolRequirement: protocolRequirement
        )
      }
    }
  }

  static func writeMethod(leadingTrivia: Trivia? = nil, typeName: String, typeSchema ts: TypeSchema, defMap: ExtDefMap, prefix: String, protocolRequirement: Bool) -> DeclSyntaxProtocol {
    switch ts.type {
    case .procedure(let def):
      ts.writeProcedure(leadingTrivia: nil, def: def, typeName: typeName, defMap: defMap, prefix: prefix, protocolRequirement: protocolRequirement)
    case .query(let def):
      ts.writeQuery(leadingTrivia: nil, def: def, typeName: typeName, defMap: defMap, prefix: prefix, protocolRequirement: protocolRequirement)
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
                      value: MemberAccessExprSyntax(parts: Lex.enumIdentifiersFor(prefix: recordType.prefix) + [.identifier(name), .keyword(.self)]),
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
    prefix.split(separator: ".").map({ $0.capitalized }).joined(separator: ".")
  }

  static func enumNameFor(prefix: String) -> String {
    "\(prefix.split(separator: ".").joined())types"
  }

  static func enumIdentifiersFor(prefix: String) -> [TokenSyntax] {
    prefix.split(separator: ".").map({ .identifier(.init(String($0).capitalized)) })
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
