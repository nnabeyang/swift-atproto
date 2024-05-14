import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

struct TypeInfo {
    let name: String
    let type: TypeSchema
}

final class Schema: Codable {
    var prefix = ""

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lexicon = try container.decode(Int.self, forKey: .lexicon)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        defs = try container.decode([String: TypeSchema].self, forKey: .defs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lexicon, forKey: .lexicon)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(defs, forKey: .defs)
    }

    func allTypes(prefix: String) -> [String: TypeSchema] {
        var out = [String: TypeSchema]()
        let id = id
        var walk: ((String, TypeSchema?) -> Void)? = nil
        walk = { (name: String, ts: TypeSchema?) in
            guard let ts else {
                fatalError(#"nil type schema in "\#(name)"(\#(self.id)) "#)
            }
            ts.prefix = prefix
            ts.id = id
            switch ts.type {
            case let .object(def):
                out[name] = ts
                for (key, val) in def.properties {
                    let childname = "\(name)_\(key.titleCased())"
                    let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
                    walk?(childname, ts)
                }
            case let .union(def):
                guard !def.refs.isEmpty else { return }
                out[name] = ts
            case let .array(def):
                let key = "\(name)_Elem"
                let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: def.items)
                walk?(key, ts)
            case .ref:
                break
            case let .procedure(def as HTTPAPITypeDefinition), let .query(def as HTTPAPITypeDefinition):
                if let input = def.input, let schema = input.schema {
                    walk?("\(name)_Input", schema)
                }
                if let output = def.output, let schema = output.schema {
                    walk?("\(name)_Output", schema)
                }
            case let .record(def):
                let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: "", type: .object(def.record), needsType: true)
                walk?(name, ts)
            default:
                break
            }
        }
        let tname = Lex.nameFromId(id: id, prefix: prefix)
        for elem in defs {
            let name = elem.key
            let n: String = if name == "main" {
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

class TypeSchema: Codable {
    var prefix = ""
    var id = ""
    var defName = ""

    let type: FieldTypeDefinition
    let needsType: Bool

    init(id: String, prefix: String, defName: String, type: FieldTypeDefinition, needsType: Bool = false) {
        self.id = id
        self.prefix = prefix
        self.defName = defName
        self.type = type
        self.needsType = TypeSchema.fix(type: type, needsType: needsType)
    }

    required init(from decoder: Decoder) throws {
        type = try FieldTypeDefinition(from: decoder)
        needsType = TypeSchema.fix(type: type, needsType: false)
    }

    private static func fix(type: FieldTypeDefinition, needsType: Bool) -> Bool {
        switch type {
        case let .object(def):
            def.properties.isEmpty ? true : needsType
        default:
            needsType
        }
    }

    func encode(to encoder: Encoder) throws {
        try type.encode(to: encoder)
    }

    func lookupRef(ref: String, defMap: ExtDefMap) -> TypeSchema {
        let fqref: String = if ref.hasPrefix("#") {
            "\(id)\(ref)"
        } else {
            ref
        }
        guard let rr = defMap[fqref] else {
            fatalError("no such ref: \(fqref)")
        }
        return rr.type
    }

    func namesFromRef(ref: String, defMap: ExtDefMap) -> (String, String) {
        let ts = lookupRef(ref: ref, defMap: defMap)
        if ts.prefix == "" {
            fatalError("no prefix for referenced type: \(ts.id)")
        }
        if prefix == "" {
            fatalError(#"no prefix for referencing type: \#(id) \#(defName)"#)
        }
        if case .string = ts.type {
            return ("INVALID", "String")
        }
        let tname: String = if ts.prefix == prefix {
            ts.typeName
        } else {
            "\(Lex.structNameFor(prefix: ts.prefix)).\(ts.typeName)"
        }
        let vname: String = if tname.contains(where: { $0 == "." }) {
            String(tname.split(separator: ".")[1])
        } else {
            tname
        }
        return (vname, tname)
    }

    var typeName: String {
        guard !id.isEmpty else {
            fatalError("type schema hint fields not set")
        }
        guard !prefix.isEmpty else {
            fatalError("why no prefix?")
        }
        let baseType: String = if defName != "main" {
            "\(Lex.nameFromId(id: id, prefix: prefix))_\(defName.titleCased())"
        } else {
            Lex.nameFromId(id: id, prefix: prefix)
        }
        if case let .array(def) = type {
            if case .union = def.items {
                return "[\(baseType)_Elem]"
            } else {
                return "[\(baseType)]"
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

    static func typeNameForField(name: String, k: String, v: TypeSchema, defMap: ExtDefMap, isRequired: Bool = true) -> String {
        let baseType: String = {
            switch v.type {
            case .boolean:
                return "Bool"
            case .blob:
                return "LexBlob"
            case .bytes:
                return "Data"
            case .string:
                return "String"
            case .integer:
                return "Int"
            case .unknown:
                return "LexiconTypeDecoder"
            case .cidLink:
                return "LexLink"
            case let .ref(def):
                let (_, tn) = v.namesFromRef(ref: def.ref, defMap: defMap)
                return tn
            case let .array(def):
                let ts = TypeSchema(id: v.id, prefix: v.prefix, defName: "Elem", type: def.items)
                let subt = Self.typeNameForField(name: "\(name)_\(k.titleCased())", k: "Elem", v: ts, defMap: defMap)
                return "[\(subt)]"
            case .union:
                return "\(name)_\(k.titleCased())"
            default:
                fatalError()
            }
        }()
        return isRequired ? baseType : "\(baseType)?"
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
            "unknown"
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

    func writeRPC(leadingTrivia: Trivia? = nil, def: any HTTPAPITypeDefinition, typeName: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
        let fname = typeName
        let arguments = def.rpcArguments(ts: self, fname: fname, defMap: defMap)
        let output = def.rpcOutput(ts: self, fname: fname, defMap: defMap)
        return FunctionDeclSyntax(
            leadingTrivia: leadingTrivia,
            modifiers: [
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.static)),
            ],
            name: .identifier(typeName),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    leftParen: .leftParenToken(),
                    parameters: FunctionParameterListSyntax(arguments),
                    rightParen: .rightParenToken()
                ),
                effectSpecifiers: FunctionEffectSpecifiersSyntax(asyncSpecifier: .keyword(.async), throwsSpecifier: .keyword(.throws)),
                returnClause: output
            )
        ) {
            VariableDeclSyntax(
                bindingSpecifier: .keyword(.let)
            ) {
                if let params = def.rpcParams(id: id, prefix: prefix) {
                    PatternBindingSyntax(
                        pattern: PatternSyntax(stringLiteral: "params"),
                        typeAnnotation: params is DictionaryExprSyntax ? TypeAnnotationSyntax(
                            type: TypeSyntax(stringLiteral: "Parameters")
                        ) : nil,
                        initializer: InitializerClauseSyntax(
                            value: params
                        )
                    )
                } else {
                    PatternBindingSyntax(
                        pattern: PatternSyntax(stringLiteral: "params"),
                        typeAnnotation: TypeAnnotationSyntax(
                            type: TypeSyntax(stringLiteral: "Bool?")
                        ),
                        initializer: InitializerClauseSyntax(
                            value: ExprSyntax("nil")
                        )
                    )
                }
            }
            ReturnStmtSyntax(
                returnKeyword: .keyword(.return),
                expression: TryExprSyntax(expression:
                    AwaitExprSyntax(expression: ExprSyntax(
                        FunctionCallExprSyntax(
                            calledExpression: ExprSyntax("client.fetch"),
                            leftParen: .leftParenToken(),
                            arguments: .init([
                                LabeledExprSyntax(label: "endpoint", colon: .colonToken(), expression: StringLiteralExprSyntax(content: self.id), trailingComma: .commaToken()),
                                LabeledExprSyntax(label: "contentType", colon: .colonToken(), expression: StringLiteralExprSyntax(content: def.contentType), trailingComma: .commaToken()),
                                LabeledExprSyntax(label: "httpMethod", colon: .colonToken(), expression: ExprSyntax(stringLiteral: httpMethod), trailingComma: .commaToken()),
                                LabeledExprSyntax(label: "params", colon: .colonToken(), expression: ExprSyntax("params"), trailingComma: .commaToken()),
                                LabeledExprSyntax(label: "input", colon: .colonToken(), expression: def.inputRPCValue, trailingComma: .commaToken()),
                                LabeledExprSyntax(label: "retry", colon: .colonToken(), expression: ExprSyntax("true")),
                            ]),
                            rightParen: .rightParenToken()
                        )
                    ))
                )
            )
        }
    }

    private func initializerParameters(name: String, def: ObjectTypeDefinition, required: [String: Bool], defMap: ExtDefMap) -> [FunctionParameterSyntax] {
        var parameters = [FunctionParameterSyntax]()
        let properties = def.sortedProperties
        let count = properties.count
        var i = 0
        for (key, property) in properties {
            i += 1
            let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: property)
            let isRequired = required[key] ?? false
            let tname = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, isRequired: isRequired)
            let comma: TokenSyntax? = i == count ? nil : .commaToken()
            parameters.append(.init(firstName: .identifier(key), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
        }

        return parameters
    }

    func lex(leadingTrivia: Trivia? = nil, name: String, type typeName: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
        switch type {
        case let .object(def):
            var required = [String: Bool]()
            for req in def.required ?? [] {
                required[req] = true
            }

            for key in def.nullable ?? [] {
                required[key] = false
            }

            return ClassDeclSyntax(
                leadingTrivia: leadingTrivia,
                modifiers: [
                    DeclModifierSyntax(name: .keyword(.public)),
                ],
                name: .init(stringLiteral: name),
                inheritanceClause: InheritanceClauseSyntax {
                    InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "Codable"))
                }
            ) {
                if needsType {
                    VariableDeclSyntax(
                        modifiers: [
                            DeclModifierSyntax(name: .keyword(.public)),
                        ],
                        bindingSpecifier: .keyword(.let)
                    ) {
                        PatternBindingSyntax(
                            pattern: PatternSyntax("type"),
                            initializer: InitializerClauseSyntax(
                                value: StringLiteralExprSyntax(content: typeName)
                            )
                        )
                    }
                }
                for (key, property) in def.sortedProperties {
                    let ts = TypeSchema(id: self.id, prefix: prefix, defName: key, type: property)
                    let isRequired = required[key] ?? false
                    let tname = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, isRequired: isRequired)
                    property.variable(name: key, typeName: tname)
                }
                InitializerDeclSyntax(
                    leadingTrivia: .newlines(2),
                    modifiers: [
                        DeclModifierSyntax(name: .keyword(.public)),
                    ],
                    initKeyword: .keyword(.`init`), signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: FunctionParameterListSyntax(
                                initializerParameters(name: name, def: def, required: required, defMap: defMap)),
                            rightParen: .rightParenToken()
                        )
                    )
                ) {
                    for (key, _) in def.sortedProperties {
                        ExprSyntax(stringLiteral: #"self.\#(key) = \#(key)"#)
                    }
                }
                EnumDeclSyntax(
                    leadingTrivia: .newlines(2),
                    name: "CodingKeys",
                    inheritanceClause: InheritanceClauseSyntax {
                        InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "String"))
                        InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "CodingKey"))
                    }
                ) {
                    if needsType {
                        EnumCaseDeclSyntax(elements: EnumCaseElementListSyntax([
                            EnumCaseElementSyntax(name: "type", rawValue: InitializerClauseSyntax(
                                value: StringLiteralExprSyntax(content: "$type")
                            )),
                        ]))
                    }
                    for key in def.properties.keys.sorted() {
                        EnumCaseDeclSyntax(elements: EnumCaseElementListSyntax([EnumCaseElementSyntax(name: .init(stringLiteral: key))]))
                    }
                }
            }
        case let .union(def):
            var tss = [TypeSchema]()
            for ref in def.refs {
                let refName: String = if ref.first == "#" {
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
                ],
                name: .init(stringLiteral: name),
                inheritanceClause: InheritanceClauseSyntax {
                    InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "Codable"))
                }
            ) {
                for ts in tss {
                    let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
                    let tn = ts.prefix == prefix ? ts.typeName : "\(Lex.structNameFor(prefix: ts.prefix)).\(ts.typeName)"
                    DeclSyntax(stringLiteral: #"case \#(Lex.caseNameFromId(id: id, prefix: prefix))(\#(tn))"#)
                }

                EnumDeclSyntax(
                    leadingTrivia: .newlines(2),
                    name: "CodingKeys",
                    inheritanceClause: InheritanceClauseSyntax {
                        InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "String"))
                        InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "CodingKey"))
                    }
                ) {
                    EnumCaseDeclSyntax(elements: EnumCaseElementListSyntax([
                        EnumCaseElementSyntax(name: "type", rawValue: InitializerClauseSyntax(
                            value: StringLiteralExprSyntax(content: "$type")
                        )),
                    ]))
                }

                InitializerDeclSyntax(
                    leadingTrivia: .newlines(2),
                    modifiers: [
                        DeclModifierSyntax(name: .keyword(.public)),
                    ],
                    initKeyword: .keyword(.`init`),
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: FunctionParameterListSyntax([
                                .init(firstName: .identifier("from"), secondName: .identifier("decoder"), type: TypeSyntax(stringLiteral: "Decoder")),
                            ]),
                            rightParen: .rightParenToken()
                        ),
                        effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                    )
                ) {
                    DeclSyntax("let container = try decoder.container(keyedBy: CodingKeys.self)")
                    DeclSyntax("let type = try container.decode(String.self, forKey: .type)")
                    SwitchExprSyntax(subject: ExprSyntax(stringLiteral: "type")) {
                        for ts in tss {
                            let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
                            SwitchCaseSyntax(#"case "\#(raw: id)":"#) {
                                ExprSyntax(#"self = try .\#(raw: Lex.caseNameFromId(id: id, prefix: prefix))(.init(from: decoder))"#)
                            }
                        }
                        SwitchCaseSyntax("default:") {
                            FunctionCallExprSyntax(
                                calledExpression: ExprSyntax("fatalError"),
                                leftParen: .leftParenToken(),
                                arguments: .init([]),
                                rightParen: .rightParenToken()
                            )
                        }
                    }
                }
                FunctionDeclSyntax(
                    leadingTrivia: .newlines(2),
                    modifiers: [
                        DeclModifierSyntax(name: .keyword(.public)),
                    ],
                    name: .identifier("encode"),
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: FunctionParameterListSyntax([
                                .init(firstName: .identifier("to"), secondName: .identifier("encoder"), type: TypeSyntax(stringLiteral: "Encoder")),
                            ]),
                            rightParen: .rightParenToken()
                        ),
                        effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                    )
                ) {
                    DeclSyntax("var container = encoder.container(keyedBy: CodingKeys.self)")
                    SwitchExprSyntax(subject: ExprSyntax(stringLiteral: "self")) {
                        for ts in tss {
                            let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
                            SwitchCaseSyntax(#"case let .\#(raw: Lex.caseNameFromId(id: id, prefix: prefix))(value):"#) {
                                ExprSyntax(#"try container.encode("\#(raw: id)", forKey: .type)"#)
                                ExprSyntax("try value.encode(to: encoder)")
                            }
                        }
                    }
                }
            }
        case let .array(def):
            let key = "elem"
            let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: def.items)
            let tname = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap)
            return VariableDeclSyntax(
                leadingTrivia: leadingTrivia,
                modifiers: [
                    DeclModifierSyntax(name: .keyword(.public)),
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
        default:
            fatalError()
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
    case token
    case unknown
    case procedure
    case query
    case subscription
    case record
}

enum AtpType {
    case concrete
    case container
    case meta
    case primary
}

enum StringFormat: String, Codable {
    case atIdentifier = "at-identifier"
    case atUri = "at-uri"
    case cid
    case datetime
    case did
    case handle
    case nsid
    case uri
    case language
}

struct RecordSchema {
    let type: PrimaryType = .record
    let key: String
    let properties: [String: TypeSchema]
    let required: [String]?
    let nullable: [String]?
}

enum FieldTypeDefinition: Codable {
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
    case unknown(UnknownTypeDefinition)
    case cidLink(CidLinkTypeDefinition)
    case procedure(ProcedureTypeDefinition)
    case query(QueryTypeDefinition)
    case subscription(SubscriptionDefinition)
    case record(RecordDefinition)
    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
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
            self = try .array(ArrayTypeDefinition(from: decoder))
        case .object:
            self = try .object(ObjectTypeDefinition(from: decoder))
        case .ref:
            self = try .ref(ReferenceTypeDefinition(from: decoder))
        case .unknown:
            self = try .unknown(UnknownTypeDefinition(from: decoder))
        case .cidLink:
            self = try .cidLink(CidLinkTypeDefinition(from: decoder))
        case .procedure:
            self = try .procedure(ProcedureTypeDefinition(from: decoder))
        case .query:
            self = try .query(QueryTypeDefinition(from: decoder))
        case .subscription:
            self = try .subscription(SubscriptionDefinition(from: decoder))
        case .record:
            self = try .record(RecordDefinition(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .token(def):
            try def.encode(to: encoder)
        case let .null(def):
            try def.encode(to: encoder)
        case let .boolean(def):
            try def.encode(to: encoder)
        case let .integer(def):
            try def.encode(to: encoder)
        case let .blob(def):
            try def.encode(to: encoder)
        case let .bytes(def):
            try def.encode(to: encoder)
        case let .string(def):
            try def.encode(to: encoder)
        case let .union(def):
            try def.encode(to: encoder)
        case let .array(def):
            try def.encode(to: encoder)
        case let .object(def):
            try def.encode(to: encoder)
        case let .ref(def):
            try def.encode(to: encoder)
        case let .unknown(def):
            try def.encode(to: encoder)
        case let .cidLink(def):
            try def.encode(to: encoder)
        case let .procedure(def):
            try def.encode(to: encoder)
        case let .query(def):
            try def.encode(to: encoder)
        case let .subscription(def):
            try def.encode(to: encoder)
        case let .record(def):
            try def.encode(to: encoder)
        }
    }

    func variable(name: String, typeName: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: [
                DeclModifierSyntax(name: .keyword(.public)),
            ],
            bindingSpecifier: .keyword(.var)
        ) {
            PatternBindingSyntax(
                pattern: PatternSyntax(stringLiteral: name),
                typeAnnotation: TypeAnnotationSyntax(
                    type: TypeSyntax(stringLiteral: typeName)
                )
            )
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

struct NullTypeDefinition: Codable {
    var type: FieldType { .boolean }
    let description: String?

    private enum TypedCodingKeys: String, CodingKey {
        case type
        case description
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(`default`, forKey: .default)
        try container.encodeIfPresent(const, forKey: .const)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(minimum, forKey: .minimum)
        try container.encodeIfPresent(maximum, forKey: .maximum)
        try container.encodeIfPresent(`enum`, forKey: .enum)
        try container.encodeIfPresent(`default`, forKey: .default)
        try container.encodeIfPresent(const, forKey: .const)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(accept, forKey: .accept)
        try container.encodeIfPresent(maxSize, forKey: .maxSize)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(minLength, forKey: .minLength)
        try container.encodeIfPresent(maxLength, forKey: .maxLength)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(maxLength, forKey: .maxLength)
        try container.encodeIfPresent(minLength, forKey: .minLength)
        try container.encodeIfPresent(maxGraphemes, forKey: .maxGraphemes)
        try container.encodeIfPresent(minGraphemes, forKey: .minGraphemes)
        try container.encodeIfPresent(knownValues, forKey: .knownValues)
        try container.encodeIfPresent(`enum`, forKey: .enum)
        try container.encodeIfPresent(const, forKey: .const)
    }
}

struct ObjectTypeDefinition: Codable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(nullable, forKey: .nullable)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(ref, forKey: .ref)
    }
}

struct UnionTypeDefinition: Codable {
    var type: FieldType { .union }
    let description: String?
    let refs: [String]
    let closed: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case refs
        case closed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        refs = try container.decode([String].self, forKey: .refs)
        closed = try container.decodeIfPresent(Bool.self, forKey: .closed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(refs, forKey: .refs)
        try container.encodeIfPresent(closed, forKey: .closed)
    }
}

struct ArrayTypeDefinition: Codable {
    var type: FieldType { .array }
    var items: FieldTypeDefinition {
        _items as! FieldTypeDefinition
    }

    let description: String?
    let minLength: Int?
    let maxLength: Int?

    private let _items: Any

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case minLength
        case maxLength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        _items = try container.decode(FieldTypeDefinition.self, forKey: .items)
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

struct UnknownTypeDefinition: Codable {
    var type: FieldType { .unknown }

    private enum TypedCodingKeys: String, CodingKey {
        case type
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
    }
}

struct CidLinkTypeDefinition: Codable {
    var type: FieldType { .cidLink }

    private enum TypedCodingKeys: String, CodingKey {
        case type
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)
    }
}

enum EncodingType: String, Codable {
    case cbor = "application/cbor"
    case json = "application/json"
    case jsonl = "application/jsonl"
    case car = "application/vnd.ipld.car"
    case text = "text/plain"
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

struct OutputType: Codable {
    let encoding: EncodingType
    let schema: TypeSchema?
    let description: String?
}

struct MessageType: Codable {
    let description: String?
    let schema: TypeSchema
}

typealias InputType = OutputType

struct Parameters: Codable {
    var type: String {
        "params"
    }

    let required: [String]?
    let properties: [String: FieldTypeDefinition]

    private enum TypedCodingKeys: String, CodingKey {
        case type
        case properties
        case required
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)

        try container.encode(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
    }

    var sortedProperties: [(String, FieldTypeDefinition)] {
        properties.keys.sorted().compactMap {
            guard let property = properties[$0] else { return nil }
            return ($0, property)
        }
    }
}

protocol HTTPAPITypeDefinition: Codable {
    var type: FieldType { get }
    var parameters: Parameters? { get }
    var output: OutputType? { get }
    var input: InputType? { get }
    var description: String? { get }

    var contentType: String { get }
    var inputRPCValue: ExprSyntax { get }
    func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap) -> [FunctionParameterSyntax]
    func rpcOutput(ts: TypeSchema, fname: String, defMap: ExtDefMap) -> ReturnClauseSyntax
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
            case .json, .jsonl, .text:
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

    func rpcArguments(ts: TypeSchema, fname: String, defMap: ExtDefMap) -> [FunctionParameterSyntax] {
        var arguments = [FunctionParameterSyntax]()
        let comma: TokenSyntax? = (input == nil && (parameters == nil || (parameters?.properties.isEmpty ?? false))) ? nil : .commaToken()
        arguments.append(.init(firstName: .identifier("client"), type: TypeSyntax("any XRPCClientProtocol"), trailingComma: comma))
        if let input {
            switch input.encoding {
            case .cbor, .any, .car:
                let tname = "Data"
                let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
                arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
            case .text:
                let tname = "String"
                let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
                arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
            case .json, .jsonl:
                let tname = "\(fname)_Input"
                let comma: TokenSyntax? = (parameters == nil || (parameters?.properties.isEmpty ?? false)) ? nil : .commaToken()
                arguments.append(.init(firstName: .identifier("input"), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
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
                let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
                let isRequired = required[name] ?? false
                let tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, isRequired: isRequired)
                let comma: TokenSyntax? = i == count ? nil : .commaToken()
                arguments.append(.init(firstName: .identifier(name), type: TypeSyntax(stringLiteral: tn), trailingComma: comma))
            }
        }
        return arguments
    }

    func rpcOutput(ts: TypeSchema, fname: String, defMap: ExtDefMap) -> ReturnClauseSyntax {
        if let output {
            switch output.encoding {
            case .json, .jsonl:
                guard let schema = output.schema else {
                    return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "EmptyResponse"))
                }
                let outname: String
                if case let .ref(def) = schema.type {
                    (_, outname) = ts.namesFromRef(ref: def.ref, defMap: defMap)
                } else {
                    outname = "\(fname)_Output"
                }
                return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: outname))
            case .text:
                return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "String"))
            case .cbor, .car, .any:
                return ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "Data"))
            }
        }
        return ReturnClauseSyntax(type: TypeSyntax("Bool"))
    }

    func rpcParams(id: String, prefix: String) -> ExprSyntaxProtocol? {
        if let parameters, !parameters.properties.isEmpty {
            DictionaryExprSyntax {
                for (name, t) in parameters.sortedProperties {
                    let ts = TypeSchema(id: id, prefix: prefix, defName: name, type: t)
                    let tn = TypeSchema.paramNameForField(typeSchema: ts)
                    DictionaryElementSyntax(
                        key: StringLiteralExprSyntax(content: name),
                        value: ExprSyntax(stringLiteral: ".\(tn)(\(name))")
                    )
                }
            }
        } else {
            nil
        }
    }
}

struct ProcedureTypeDefinition: HTTPAPITypeDefinition {
    var type: FieldType { .procedure }
    let parameters: Parameters?
    let output: OutputType?
    let input: InputType?
    let description: String?
}

struct QueryTypeDefinition: HTTPAPITypeDefinition {
    var type: FieldType { .query }
    let parameters: Parameters?
    let output: OutputType?
    let input: InputType?
    let description: String?
}

struct SubscriptionDefinition: Codable {
    var type: FieldType {
        .subscription
    }

    let parameters: Parameters?
    let message: MessageType?

    private enum TypedCodingKeys: String, CodingKey {
        case type
        case parameters
        case message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)

        try container.encodeIfPresent(parameters, forKey: .parameters)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

struct RecordDefinition: Codable {
    var type: FieldType {
        .record
    }

    let key: String
    let record: ObjectTypeDefinition

    private enum TypedCodingKeys: String, CodingKey {
        case type
        case key
        case record
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.TypedCodingKeys.self)
        try container.encode(type, forKey: .type)

        try container.encode(key, forKey: .key)
        try container.encode(record, forKey: .record)
    }
}
