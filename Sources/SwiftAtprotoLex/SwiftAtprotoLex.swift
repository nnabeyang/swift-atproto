import Foundation
import SwiftBasicFormat
import SwiftSyntax
import SwiftSyntaxBuilder

#if os(macOS) || os(Linux)
  import SourceControl
#endif

public func main(outdir outdirBaseURL: URL, path: String, generate: GenerateOption, pluginSource: PluginSource = .command) async throws {
  let url = URL(filePath: path)

  let fileURLs = collectJSONFileURLs(at: url)
  let schemasMap = try await decodeSchemasByPrefix(from: fileURLs)
  let defMap = Lex.buildExtDefMap(schemasMap: schemasMap)
  try await writeSchemaCode(for: schemasMap, with: defMap, to: outdirBaseURL, generate: generate, pluginSource: pluginSource)
}

func collectJSONFileURLs(at baseURL: URL) -> [URL] {
  // `FileManager.enumerator` does not traverse symbolic links, so it would
  // miss local lexicon trees installed under `.lexicons/lexicons/` as symlinks.
  // Walk the tree manually instead, resolving each entry's target so
  // symlinked lexicon trees are discovered as if they were physically nested.
  var fileURLs = [URL]()
  var visited = Set<String>()
  walkLexicons(at: baseURL, visited: &visited, into: &fileURLs)
  return fileURLs
}

private func walkLexicons(at url: URL, visited: inout Set<String>, into result: inout [URL]) {
  let target = url.resolvingSymlinksInPath()
  // Detect symlink cycles (and reentry into a shared subtree) by remembering
  // each directory's resolved physical path. Without this guard a `foo -> .`
  // symlink would recurse until the stack overflows.
  let visitedKey = target.standardizedFileURL.path
  guard visited.insert(visitedKey).inserted else { return }
  guard
    let entries = try? FileManager.default.contentsOfDirectory(
      at: target,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants])
  else { return }
  for entry in entries {
    let logical = url.appending(component: entry.lastPathComponent)
    let physical = entry.resolvingSymlinksInPath()
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: physical.path, isDirectory: &isDir) else {
      continue
    }
    if isDir.boolValue {
      walkLexicons(at: logical, visited: &visited, into: &result)
    } else if logical.pathExtension == "json" {
      result.append(logical)
    }
  }
}

enum SchemaDecodeError: Error, CustomStringConvertible {
  case duplicateNSID(id: String, firstPath: URL, secondPath: URL)

  var description: String {
    switch self {
    case .duplicateNSID(let id, let firstPath, let secondPath):
      return "duplicate NSID \(id) loaded from both \(firstPath.path) and \(secondPath.path)"
    }
  }
}

func decodeSchemasByPrefix(from fileURLs: [URL]) async throws -> [String: [Schema]] {
  let decoder = JSONDecoder()
  let entries: [(URL, Schema)] = try await withThrowingTaskGroup(of: (URL, Schema).self) { group in
    for fileURL in fileURLs {
      group.addTask {
        let data = try Data(contentsOf: fileURL)
        let schema = try decoder.decode(Schema.self, from: data)
        return (fileURL, schema)
      }
    }
    var out: [(URL, Schema)] = []
    for try await pair in group {
      out.append(pair)
    }
    return out
  }
  // Sort so duplicate-NSID errors report a stable "first" / "second" pair
  // regardless of task completion order.
  let sortedEntries = entries.sorted { $0.0.path < $1.0.path }

  var seen: [String: URL] = [:]
  var schemasMap: [String: [Schema]] = [:]
  for (fileURL, schema) in sortedEntries {
    if let firstPath = seen[schema.id] {
      throw SchemaDecodeError.duplicateNSID(id: schema.id, firstPath: firstPath, secondPath: fileURL)
    }
    seen[schema.id] = fileURL
    schemasMap[schema.prefix, default: []].append(schema)
  }
  return schemasMap
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
  generate: GenerateOption,
  pluginSource: PluginSource
) async throws {
  let schemasArray = schemasMap.sorted { $0.key < $1.key }
  let (blocks, methods, requirements) = try await withThrowingTaskGroup(of: (DeclSyntax, MemberBlockItemListSyntax, MemberBlockItemListSyntax, Int).self) { group in
    let src = Lex.genUnknownRecord(for: schemasMap)
    let recordURL = baseURL.appending(path: "UnknownATPValue.swift")
    try src.write(to: recordURL, atomically: true, encoding: .utf8)
    let serverURL = baseURL.appending(path: "XRPCAPIProtocol.swift")
    switch (generate.contains(.server), pluginSource) {
    case (true, _):
      let serverSrc = Lex.genXRPCAPIProtocolFile(for: schemasMap, defMap: defMap)
      try serverSrc.write(to: serverURL, atomically: true, encoding: .utf8)
    case (false, .build):
      // The build plugin pre-declares this file as an output at plan time, so
      // write a header-only placeholder that compiles cleanly. Any
      // pre-existing content from an earlier `.server` run is overwritten.
      let placeholder = Lex.renderSourceFile(SourceFileSyntax(leadingTrivia: Lex.fileHeader) {})
      try placeholder.write(to: serverURL, atomically: true, encoding: .utf8)
    case (false, .command):
      // XRPCAPIProtocol.swift is a fixed, swift-atproto-owned filename, so a
      // leftover at this path is always a prior-run artifact (including the
      // 0-byte placeholders written by older versions). Drop it unconditionally.
      if FileManager.default.fileExists(atPath: serverURL.path) {
        try FileManager.default.removeItem(at: serverURL)
      }
    }
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
              let methods = Lex.genMethods(leadingTrivia: allTypes.isEmpty ? nil : .newline, prefix: prefix, methods: methodTypes, defMap: defMap, generate: generate, protocolRequirement: false)
              let requirements = Lex.genMethods(leadingTrivia: allTypes.isEmpty ? nil : .newline, prefix: prefix, methods: methodTypes, defMap: defMap, generate: generate, protocolRequirement: true)
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
              leadingTrivia: .newlines(2),
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
  // A record NSID can also be a namespace prefix when deeper NSIDs exist. In
  // that case, the namespace tree and record declaration can emit the same
  // Swift name. Detect that overlap and attach the sub-namespaces to the
  // record instead of emitting a conflicting namespace enum.
  // Only ids whose derived struct name is a single Swift identifier can
  // collide with a same-named namespace enum. That happens exactly when the
  // trimmed portion (id minus prefix) is a single NSID segment — with the
  // `count >= 4 ? drop 2 : drop 1` prefix rule, that means ids with 2 or 3
  // segments. Longer ids camel-case the tail and therefore live alongside
  // the namespace enums, not on top of them.
  let candidateIds = Set(schemasMap.values.flatMap { $0.map(\.id) })
    .filter {
      let count = $0.split(separator: ".").count
      return count == 2 || count == 3
    }
  let namespaceCollisions = candidateIds.intersection(schemasMap.keys)
  let namespaceRoots = EnumDeclSyntaxNode.buildTree(from: prefixes)
  var collisionExtensions: [(nsidPath: [String], children: [EnumDeclSyntaxNode])] = []
  for root in namespaceRoots {
    EnumDeclSyntaxNode.extractCollisionExtensions(root, path: [root.segment], collisions: namespaceCollisions, into: &collisionExtensions)
  }
  let clientTree = SourceFileSyntax(leadingTrivia: Lex.fileHeader) {
    ImportDeclSyntax(
      path: [ImportPathComponentSyntax(name: "Foundation")]
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
        ]
      )
    }
    ImportDeclSyntax(
      path: [ImportPathComponentSyntax(name: "SwiftAtproto")],
      trailingTrivia: .newlines(2)
    )
    for (i, node) in namespaceRoots.enumerated() {
      node.generateEnums(leadingTrivia: i == 0 ? nil : .newlines(2))
    }
    for ext in collisionExtensions {
      ExtensionDeclSyntax(
        leadingTrivia: .newlines(2),
        extendedType: TypeSyntax(MemberTypeSyntax(parts: ext.nsidPath.map { .lexIdentifier($0.capitalized) }))
      ) {
        for child in ext.children {
          child.generateEnums()
        }
      }
    }
    blocks
    if !methods.isEmpty {
      ProtocolDeclSyntax(
        leadingTrivia: .newlines(2),
        modifiers: [
          DeclModifierSyntax(name: .keyword(.public))
        ],
        name: .identifier("XRPCCallable"),
        inheritanceClause: InheritanceClauseSyntax(typeNames: ["_XRPCCallable"])
      ) {
        requirements
      }
      ExtensionDeclSyntax(leadingTrivia: .newlines(2), extendedType: TypeSyntax(stringLiteral: "XRPCCallable")) {
        methods
      }
    }
  }
  let clientSrc: String = Lex.renderSourceFile(clientTree)
  let clientURL = baseURL.appending(path: "XRPCAPIClient.swift")
  try clientSrc.write(to: clientURL, atomically: true, encoding: .utf8)
}

class EnumDeclSyntaxNode {
  let segment: String
  let name: String
  var children: [String: EnumDeclSyntaxNode] = [:]

  init(segment: String) {
    self.segment = segment
    self.name = segment.capitalized
  }

  func generateEnums(leadingTrivia: Trivia? = nil, depth: Int = 0) -> EnumDeclSyntax {
    let lt: Trivia? = depth > 0 ? .newline : leadingTrivia
    return EnumDeclSyntax(
      leadingTrivia: lt,
      modifiers: [
        DeclModifierSyntax(name: .keyword(.public))
      ],
      name: .lexIdentifier(name)
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
        roots[firstPart] = EnumDeclSyntaxNode(segment: firstPart)
      }

      var current = roots[firstPart]!
      for part in parts.dropFirst() {
        if current.children[part] == nil {
          current.children[part] = EnumDeclSyntaxNode(segment: part)
        }
        current = current.children[part]!
      }
    }
    return roots.values.sorted { $0.name < $1.name }
  }

  /// Descends into `node` and, for any child whose full NSID path is in
  /// `collisions`, removes the node from the tree and records a
  /// `(nsidPath, children)` tuple in `into`. The caller emits each tuple as
  /// `extension <Capitalized.Path> { <children as nested enums> }`, so the
  /// namespace sub-hierarchy lives on the same Swift name as the record
  /// struct/enum without redeclaring it. Nested collisions are surfaced by
  /// recursing before extracting, so an inner collision produces its own
  /// extension.
  static func extractCollisionExtensions(
    _ node: EnumDeclSyntaxNode,
    path: [String],
    collisions: Set<String>,
    into extensions: inout [(nsidPath: [String], children: [EnumDeclSyntaxNode])]
  ) {
    for childKey in Array(node.children.keys) {
      let child = node.children[childKey]!
      let childPath = path + [child.segment]
      let childNsid = childPath.joined(separator: ".")
      if collisions.contains(childNsid) {
        // Recurse first so any deeper collisions inside `child` also get
        // extracted (rather than collapsing into this extension's body).
        extractCollisionExtensions(child, path: childPath, collisions: collisions, into: &extensions)
        let subChildren = child.children.keys.sorted().map { child.children[$0]! }
        if !subChildren.isEmpty {
          extensions.append((nsidPath: childPath, children: subChildren))
        }
        node.children.removeValue(forKey: childKey)
      } else {
        extractCollisionExtensions(child, path: childPath, collisions: collisions, into: &extensions)
      }
    }
  }
}

enum Lex {
  // Render a `SourceFileSyntax` through the project's standard formatter and
  // append a trailing newline. Centralized so the build-plugin placeholder and
  // the real client/protocol files always emit identical headers and spacing.
  static func renderSourceFile(_ source: SourceFileSyntax) -> String {
    source.formatted(using: BasicFormat(indentationWidth: .spaces(2)))
      .with(\.trailingTrivia, .newline)
      .description
  }

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
      .newlines(1),
      .lineComment("// swift-format-ignore-file"),
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
        EnumCaseDeclSyntax(leadingTrivia: .newline) {
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
        EnumCaseDeclSyntax(leadingTrivia: .newline) {
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
          leadingTrivia: [.newlines(2)],
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
                value: DictionaryExprSyntax(rightSquare: .rightSquareToken(leadingTrivia: .newline)) {
                  for (name, recordType) in recordTypes.sorted(by: { $0.value.id < $1.value.id }) {
                    DictionaryElementSyntax(
                      key: StringLiteralExprSyntax(openingQuote: .stringQuoteToken(leadingTrivia: .newline), content: recordType.id),
                      colon: .colonToken(),
                      value: MemberAccessExprSyntax(parts: Lex.enumIdentifiersFor(prefix: recordType.prefix) + [.lexIdentifier(name), .keyword(.self)]),
                      trailingComma: .commaToken()
                    )
                  }
                }
              )
            )
          ]
        )
        VariableDeclSyntax(
          leadingTrivia: [.newlines(2)],
          modifiers: [
            DeclModifierSyntax(name: .keyword(.public))
          ],
          bindingSpecifier: .keyword(.var),
          bindings: [
            PatternBindingSyntax(
              pattern: IdentifierPatternSyntax(identifier: .identifier("type")),
              typeAnnotation: TypeAnnotationSyntax(
                colon: .colonToken(),
                type: OptionalTypeSyntax(wrappedType: Lex.typeSyntax("Swift.String"))
              ),
              accessorBlock: AccessorBlockSyntax(
                leftBrace: .leftBraceToken(),
                accessors: .getter(
                  CodeBlockItemListSyntax {
                    ExpressionStmtSyntax(
                      expression: SwitchExprSyntax(
                        leadingTrivia: .newline,
                        subject: DeclReferenceExprSyntax(baseName: .keyword(.self))
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
                            leadingTrivia: .newline,
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
                              leadingTrivia: .newline,
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
                            leadingTrivia: .newline,
                            expression: NilLiteralExprSyntax()
                          )
                        }
                      }
                      .with(
                        \.rightBrace, .rightBraceToken(leadingTrivia: .newline)
                      ))
                  }),
                rightBrace: .rightBraceToken(leadingTrivia: .newline)
              )
            )
          ]
        )
        VariableDeclSyntax(
          leadingTrivia: [.newlines(2)],
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
                        leadingTrivia: .newline,
                        subject: DeclReferenceExprSyntax(baseName: .keyword(.self))
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
                          DeclReferenceExprSyntax(baseName: .identifier("record", leadingTrivia: .newline))
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
                              DeclReferenceExprSyntax(baseName: .identifier("object", leadingTrivia: .newline))
                            ))
                        }
                      }
                      .with(\.rightBrace, .rightBraceToken(leadingTrivia: .newline))
                    )
                  }),
                rightBrace: .rightBraceToken(leadingTrivia: .newline)
              )
            )
          ]
        )
      }
    }
    .with(\.trailingTrivia, .newline)
    return src.formatted(using: BasicFormat(indentationWidth: .spaces(2))).description
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
    prefix.split(separator: ".").joined()
  }

  static func enumIdentifiersFor(prefix: String) -> [TokenSyntax] {
    prefix.split(separator: ".").map({ .lexIdentifier(String($0).capitalized) })
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
