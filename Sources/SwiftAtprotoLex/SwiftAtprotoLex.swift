import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

public func main(outdir: String, path: String) throws {
    let decoder = JSONDecoder()
    var schemas = [Schema]()
    let url = URL(filePath: path)
    var prefixes = Set<String>()
    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
        for case let fileUrl as URL in enumerator {
            do {
                let fileAttributes = try fileUrl.resourceValues(forKeys: [.isRegularFileKey])
                if fileAttributes.isRegularFile!, fileUrl.pathExtension == "json" {
                    prefixes.insert(fileUrl.prefix(baseURL: url))
                    let json = try String(contentsOf: fileUrl, encoding: .utf8)
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
        let src = Lex.baseFile(prefix: prefix)
        try src.write(to: fileUrl, atomically: true, encoding: .utf8)
        for schema in schemas {
            guard schema.id.hasPrefix(prefix) else { continue }
            let fileUrl = outdirURL.appending(path: "\(filePrefix)_\(schema.name).swift")
            let src = Lex.genCode(for: schema, prefix: prefix, defMap: defmap)
            try src.write(to: fileUrl, atomically: true, encoding: .utf8)
        }
    }
}

private extension URL {
    func prefix(baseURL: URL) -> String {
        precondition(path.hasPrefix(baseURL.path))
        let relativeCount = pathComponents.count - baseURL.pathComponents.count
        let url = relativeCount >= 4 ? deletingLastPathComponent() : self
        return url.deletingLastPathComponent().path.dropFirst(baseURL.path.count + 1).replacingOccurrences(of: "/", with: ".")
    }
}

enum Lex {
    private static var fileHeader: Trivia {
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
        let src = SourceFileSyntax(leadingTrivia: Self.fileHeader, statementsBuilder: {
            ImportDeclSyntax(
                path: ImportPathComponentListSyntax([ImportPathComponentSyntax(name: "SwiftAtproto")]),
                trailingTrivia: .newlines(2)
            )
            EnumDeclSyntax(
                modifiers: [
                    DeclModifierSyntax(name: .keyword(.public)),
                ],
                name: .identifier(Lex.structNameFor(prefix: prefix)),
                memberBlock: MemberBlockSyntax(
                    leftBrace: .leftBraceToken(),
                    members: MemberBlockItemListSyntax([]),
                    rightBrace: .rightBraceToken()
                )
            )
        },
        trailingTrivia: .newline)
        return src.formatted().description
    }

    static func genCode(for schema: Schema, prefix: String, defMap: ExtDefMap) -> String {
        schema.prefix = prefix
        let structName = Lex.structNameFor(prefix: prefix)
        let allTypes = schema.allTypes(prefix: prefix).sorted(by: {
            $0.key.localizedStandardCompare($1.key) == .orderedAscending
        })
        let recordTypes = allTypes.filter(\.value.isRecord)
        let otherTypes = allTypes.filter { !$0.value.isRecord }
        let methods: [DeclSyntaxProtocol]? = if let main = schema.defs["main"],
                                                main.isMethod
        {
            Self.writeMethods(
                leadingTrivia: otherTypes.isEmpty ? nil : .newlines(2),
                typeName: Self.nameFromId(id: schema.id, prefix: prefix),
                typeSchema: main,
                defMap: defMap,
                prefix: structNameFor(prefix: prefix)
            )
        } else {
            nil
        }
        let enumExtensionIsNeeded = !otherTypes.isEmpty || methods != nil
        let src = SourceFileSyntax(leadingTrivia: Self.fileHeader, statementsBuilder: {
            ImportDeclSyntax(
                path: ImportPathComponentListSyntax([ImportPathComponentSyntax(name: "SwiftAtproto")])
            )
            ImportDeclSyntax(
                path: ImportPathComponentListSyntax([ImportPathComponentSyntax(name: "Foundation")]),
                trailingTrivia: .newlines(2)
            )
            if enumExtensionIsNeeded {
                ExtensionDeclSyntax(extendedType: TypeSyntax(stringLiteral: structName)) {
                    for (i, (name, ot)) in otherTypes.enumerated() {
                        ot.lex(leadingTrivia: i == 0 ? nil : .newlines(2), name: name, type: (ot.defName.isEmpty || ot.defName == "main") ? ot.id : "\(ot.id)#\(ot.defName)", defMap: defMap)
                    }

                    if let methods, methods.count == 2 {
                        methods[0]
                    }
                }
            }
            if let methods, let method = methods.last {
                ExtensionDeclSyntax(extendedType: TypeSyntax(stringLiteral: "XRPCClientProtocol")) {
                    method
                }
            }
            for (i, (name, ot)) in recordTypes.enumerated() {
                ot.lex(leadingTrivia: (!enumExtensionIsNeeded && i == 0) ? nil : .newlines(2), name: name, type: (ot.defName.isEmpty || ot.defName == "main") ? ot.id : "\(ot.id)#\(ot.defName)", defMap: defMap)
            }
        },
        trailingTrivia: .newline)
        return src.formatted().description
    }

    static func writeMethods(leadingTrivia: Trivia? = nil, typeName: String, typeSchema ts: TypeSchema, defMap: ExtDefMap, prefix: String) -> [DeclSyntaxProtocol]? {
        switch ts.type {
        case .token:
            let n: String = if ts.defName == "main" {
                ts.id
            } else {
                "\(ts.id)#\(ts.defName)"
            }
            let variable = VariableDeclSyntax(
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
            return [variable]
        case let .procedure(def as HTTPAPITypeDefinition), .query(let def as HTTPAPITypeDefinition):
            return [
                ts.writeErrorDecl(leadingTrivia: leadingTrivia, def: def, typeName: typeName, defMap: defMap),
                ts.writeRPC(leadingTrivia: nil, def: def, typeName: typeName, defMap: defMap, prefix: prefix),
            ].compactMap(\.self)
        default:
            return nil
        }
    }

    static func buildExtDefMap(schemas: [Schema], prefixes: Set<String>) -> ExtDefMap {
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

    func camelCased() -> String {
        guard !isEmpty else { return "" }
        let words = components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let first = words.first!.lowercased()
        let rest = words.dropFirst().map(\.capitalized)
        return ([first] + rest).joined()
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
