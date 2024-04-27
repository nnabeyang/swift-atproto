import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

public var version: String { "0.6.0" }

public func main(outdir: String, path: String) throws {
    let decoder = JSONDecoder()
    var schemas = [Schema]()
    let url = URL(filePath: path)
    var prefixes = [String]()
    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
        for case let fileUrl as URL in enumerator {
            do {
                let fileAttributes = try fileUrl.resourceValues(forKeys: [.isRegularFileKey])
                if fileAttributes.isRegularFile!, fileUrl.pathExtension == "json" {
                    let nsId = fileUrl.nsId(baseURL: url)
                    update(prefixes: &prefixes, nsId: nsId)
                    let json = try String(contentsOf: fileUrl)
                    try schemas.append(decoder.decode(Schema.self, from: Data(json.utf8)))
                }
            } catch {
                print(error, fileUrl)
            }
        }
    }

    let defmap = Lex.buildExtDefMap(schemas: schemas, prefixes: prefixes)
    let outdirBaseURL = URL(filePath: outdir)
    for prefix in prefixes {
        let filePrefix = prefix.split(separator: ".").joined()
        let outdirURL = outdirBaseURL.appending(path: filePrefix)
        if FileManager.default.fileExists(atPath: outdirURL.path) {
            try FileManager.default.removeItem(at: outdirURL)
        }
        try FileManager.default.createDirectory(at: outdirURL, withIntermediateDirectories: true)
        let enumName = Lex.structNameFor(prefix: prefix)
        let fileUrl = outdirURL.appending(path: "\(enumName).swift")
        let src = Lex.baseFile(prefix: prefix, defMap: defmap)
        try src.write(to: fileUrl, atomically: true, encoding: .utf8)
        for schema in schemas {
            guard schema.id.hasPrefix(prefix) else { continue }
            let fileUrl = outdirURL.appending(path: "\(filePrefix)_\(schema.name).swift")
            let src = Lex.genCode(for: schema, prefix: prefix, defMap: defmap)
            try src.write(to: fileUrl, atomically: true, encoding: .utf8)
        }
    }
}

func update(prefixes: inout [String], nsId: String) {
    for (i, prefix) in prefixes.enumerated() {
        let candidate = prefix.commonPrefix(with: nsId)
        if !candidate.isEmpty, prefix != nsId {
            prefixes[i] = candidate.hasSuffix(".") ? String(candidate.dropLast()) : candidate
            return
        }
    }
    prefixes.append(nsId)
}

private extension URL {
    func nsId(baseURL: URL) -> String {
        precondition(path.hasPrefix(baseURL.path))
        return deletingPathExtension().path.dropFirst(baseURL.path.count + 1).replacingOccurrences(of: "/", with: ".")
    }
}

enum Lex {
    private static let fileHeader = Trivia(pieces: [
        .lineComment("//"),
        .newlines(1),
        .lineComment("// DO NOT EDIT"),
        .newlines(1),
        .lineComment("//"),
        .newlines(1),
        .lineComment("// Generated by swift-atproto \(version)"),
        .newlines(1),
        .lineComment("//"),
        .newlines(2),
    ])

    static func baseFile(prefix: String, defMap: ExtDefMap) -> String {
        var arguments = [(id: LabeledExprSyntax, val: LabeledExprSyntax)]()
        for key in defMap.keys.sorted() {
            guard let ts = defMap[key],
                  ts.type.prefix == prefix
            else {
                continue
            }

            if case .record = ts.type.type {
                arguments.append((id: LabeledExprSyntax(label: "id", colon: .colonToken(),
                                                        expression: StringLiteralExprSyntax(content: key),
                                                        trailingComma: .commaToken()),
                                  val: LabeledExprSyntax(label: "val", colon: .colonToken(),
                                                         expression: ExprSyntax("\(raw: ts.type.typeName).self"))))
            }
        }

        let src = SourceFileSyntax(leadingTrivia: Self.fileHeader, statementsBuilder: {
            ImportDeclSyntax(
                path: ImportPathComponentListSyntax([ImportPathComponentSyntax(name: "SwiftAtproto")]),
                trailingTrivia: .newlines(2)
            )
            EnumDeclSyntax(
                modifiers: [
                    DeclModifierSyntax(name: .keyword(.public)),
                ],
                name: TokenSyntax(stringLiteral: Lex.structNameFor(prefix: prefix))
            ) {
                FunctionDeclSyntax(
                    leadingTrivia: nil,
                    modifiers: [
                        DeclModifierSyntax(name: .keyword(.public)),
                        DeclModifierSyntax(name: .keyword(.static)),
                    ],
                    name: .identifier("registerLexiconTypes"),
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: .init([]),
                            rightParen: .rightParenToken()
                        ),
                        effectSpecifiers: nil,
                        returnClause: nil
                    )
                ) {
                    for argument in arguments {
                        FunctionCallExprSyntax(
                            calledExpression: ExprSyntax("LexiconTypesMap.shared.register"),
                            leftParen: .leftParenToken(),
                            arguments: .init([
                                argument.id,
                                argument.val,
                            ]),
                            rightParen: .rightParenToken()
                        )
                    }
                }
            }
        },
        trailingTrivia: .newline)
        return src.formatted().description
    }

    static func genCode(for schema: Schema, prefix: String, defMap: ExtDefMap) -> String {
        schema.prefix = prefix
        let structName = Lex.structNameFor(prefix: prefix)
        let src = SourceFileSyntax(leadingTrivia: Self.fileHeader, statementsBuilder: {
            ImportDeclSyntax(
                path: ImportPathComponentListSyntax([ImportPathComponentSyntax(name: "SwiftAtproto")])
            )
            ImportDeclSyntax(
                path: ImportPathComponentListSyntax([ImportPathComponentSyntax(name: "Foundation")]),
                trailingTrivia: .newlines(2)
            )
            ExtensionDeclSyntax(extendedType: TypeSyntax(stringLiteral: structName)) {
                let allTypes = schema.allTypes(prefix: prefix)
                for (i, (name, ot)) in allTypes.sorted(by: {
                    $0.key.localizedStandardCompare($1.key) == .orderedAscending
                }).enumerated() {
                    ot.lex(leadingTrivia: i == 0 ? nil : .newlines(2), name: name, type: (ot.defName.isEmpty || ot.defName == "main") ? ot.id : "\(ot.id)#\(ot.defName)", defMap: defMap)
                }

                if let main = schema.defs["main"],
                   main.isMethod,
                   let method = Self.writeMethods(
                       leadingTrivia: allTypes.isEmpty ? nil : .newlines(2),
                       typeName: Self.nameFromId(id: schema.id, prefix: prefix),
                       typeSchema: main,
                       defMap: defMap
                   )
                {
                    method
                }
            }
        },
        trailingTrivia: .newline)
        return src.formatted().description
    }

    static func writeMethods(leadingTrivia: Trivia? = nil, typeName: String, typeSchema ts: TypeSchema, defMap: ExtDefMap) -> DeclSyntaxProtocol? {
        switch ts.type {
        case .token:
            let n: String = if ts.defName == "main" {
                ts.id
            } else {
                "\(ts.id)#\(ts.defName)"
            }
            return VariableDeclSyntax(
                leadingTrivia: leadingTrivia,
                modifiers: [
                    DeclModifierSyntax(name: .keyword(.public)),
                ],
                bindingSpecifier: .keyword(.let)
            ) {
                PatternBindingSyntax(
                    pattern: PatternSyntax(stringLiteral: typeName),
                    initializer: InitializerClauseSyntax(
                        value: StringLiteralExprSyntax(content: n)
                    )
                )
            }
        case let .procedure(def as HTTPAPITypeDefinition), .query(let def as HTTPAPITypeDefinition):
            return ts.writeRPC(leadingTrivia: leadingTrivia, def: def, typeName: typeName, defMap: defMap)
        default:
            return nil
        }
    }

    static func buildExtDefMap(schemas: [Schema], prefixes: [String]) -> ExtDefMap {
        var out = ExtDefMap()
        for schema in schemas {
            for (defName, def) in schema.defs {
                def.id = schema.id
                def.defName = defName

                def.prefix = {
                    for p in prefixes {
                        if schema.id.hasPrefix(p) {
                            return p
                        }
                    }
                    return ""
                }()

                let key = {
                    if defName == "main" {
                        return schema.id
                    }
                    return "\(schema.id)#\(defName)"
                }()
                out[key] = ExtDef(type: def)
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
        return String(map {
            if prev.isWhitespace {
                prev = $0
                return Character($0.uppercased())
            }
            prev = $0
            return $0
        })
    }
}

extension Substring {
    func titleCased() -> String {
        var prev = Character(" ")
        return String(map {
            if prev.isWhitespace {
                prev = $0
                return Character($0.uppercased())
            }
            prev = $0
            return $0
        })
    }
}
