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
                if let parameters = def.parameters {
                    for (key, val) in parameters.properties {
                        let childname = "\(name)_\(key.titleCased())"
                        let ts = TypeSchema(id: id, prefix: prefix, defName: childname, type: val)
                        walk?(childname, ts)
                    }
                }
            case let .record(def):
                let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: "", type: .object(def.record), needsType: true)
                walk?(name, ts)
            case let .string(def):
                guard def.knownValues != nil || def.enum != nil else { break }
                out[name] = ts
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
    let isRecord: Bool
    let needsType: Bool

    init(id: String, prefix: String, defName: String, type: FieldTypeDefinition, needsType: Bool = false) {
        self.id = id
        self.prefix = prefix
        self.defName = defName
        self.type = type
        self.needsType = TypeSchema.fix(type: type, needsType: needsType)
        isRecord = needsType
    }

    required init(from decoder: Decoder) throws {
        type = try FieldTypeDefinition(from: decoder)
        needsType = TypeSchema.fix(type: type, needsType: false)
        isRecord = false
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

    func namesFromRef(ref: String, defMap: ExtDefMap, dropPrefix: Bool = true) -> (String, String) {
        let ts = lookupRef(ref: ref, defMap: defMap)
        if ts.prefix == "" {
            fatalError("no prefix for referenced type: \(ts.id)")
        }
        if prefix == "" {
            fatalError(#"no prefix for referencing type: \#(id) \#(defName)"#)
        }
        if case let .string(def) = ts.type, def.knownValues == nil, def.enum == nil {
            return ("INVALID", "String")
        }
        let tname: String = if dropPrefix, ts.prefix == prefix {
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
                EnumCaseDeclSyntax(
                    caseKeyword: .keyword(.case),
                    elements: EnumCaseElementListSyntax([
                        EnumCaseElementSyntax(
                            name: .identifier(error.name.camelCased()),
                            parameterClause: EnumCaseParameterClauseSyntax(
                                leftParen: .leftParenToken(),
                                parameters: EnumCaseParameterListSyntax([
                                    EnumCaseParameterSyntax(type: OptionalTypeSyntax(
                                        wrappedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                                        questionMark: .postfixQuestionMarkToken()
                                    )),
                                ]),
                                rightParen: .rightParenToken()
                            )
                        ),
                    ])
                )
            }
            EnumCaseDeclSyntax(
                caseKeyword: .keyword(.case),
                elements: EnumCaseElementListSyntax([
                    EnumCaseElementSyntax(
                        name: .identifier("unexpected"),
                        parameterClause: EnumCaseParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: EnumCaseParameterListSyntax([
                                EnumCaseParameterSyntax(
                                    modifiers: DeclModifierListSyntax([]),
                                    firstName: .identifier("error"),
                                    colon: .colonToken(),
                                    type: OptionalTypeSyntax(
                                        wrappedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                                        questionMark: .postfixQuestionMarkToken()
                                    ),
                                    trailingComma: .commaToken()
                                ),
                                EnumCaseParameterSyntax(
                                    modifiers: DeclModifierListSyntax([]),
                                    firstName: .identifier("message"),
                                    colon: .colonToken(),
                                    type: OptionalTypeSyntax(
                                        wrappedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                                        questionMark: .postfixQuestionMarkToken()
                                    )
                                ),
                            ]),
                            rightParen: .rightParenToken()
                        )
                    ),
                ])
            )

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
                            .init(firstName: .identifier("error"), type: TypeSyntax(stringLiteral: "UnExpectedError")),
                        ]),
                        rightParen: .rightParenToken()
                    )
                )
            ) {
                SwitchExprSyntax(subject: ExprSyntax(stringLiteral: "error.error")) {
                    for error in errors {
                        SwitchCaseSyntax(
                            label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                                caseKeyword: .keyword(.case),
                                caseItems: SwitchCaseItemListSyntax([
                                    SwitchCaseItemSyntax(pattern: PatternSyntax(ExpressionPatternSyntax(expression: StringLiteralExprSyntax(
                                        openingQuote: .stringQuoteToken(),
                                        segments: StringLiteralSegmentListSyntax([
                                            StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(error.name))),
                                        ]),
                                        closingQuote: .stringQuoteToken()
                                    )))),
                                ]),
                                colon: .colonToken()
                            )),
                            statements: CodeBlockItemListSyntax([
                                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(SequenceExprSyntax {
                                    DeclReferenceExprSyntax(baseName: .keyword(.self))
                                    AssignmentExprSyntax(equal: .equalToken())
                                    FunctionCallExprSyntax(
                                        calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                            period: .periodToken(),
                                            declName: DeclReferenceExprSyntax(baseName: .identifier(error.name.camelCased()))
                                        )),
                                        leftParen: .leftParenToken(),
                                        arguments: LabeledExprListSyntax([
                                            LabeledExprSyntax(expression: ExprSyntax(MemberAccessExprSyntax(
                                                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error"))),
                                                period: .periodToken(),
                                                declName: DeclReferenceExprSyntax(baseName: .identifier("message"))
                                            ))),
                                        ]),
                                        rightParen: .rightParenToken(),
                                        additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                    )
                                }
                                )),
                            ])
                        )
                    }

                    SwitchCaseSyntax(
                        label: SwitchCaseSyntax.Label(SwitchDefaultLabelSyntax(
                            defaultKeyword: .keyword(.default),
                            colon: .colonToken()
                        )),
                        statements: CodeBlockItemListSyntax([
                            CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(SequenceExprSyntax {
                                DeclReferenceExprSyntax(baseName: .keyword(.self))
                                AssignmentExprSyntax(equal: .equalToken())
                                FunctionCallExprSyntax(
                                    calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                        period: .periodToken(),
                                        declName: DeclReferenceExprSyntax(baseName: .identifier("unexpected"))
                                    )),
                                    leftParen: .leftParenToken(),
                                    arguments: LabeledExprListSyntax([
                                        LabeledExprSyntax(
                                            label: .identifier("error"),
                                            colon: .colonToken(),
                                            expression: ExprSyntax(MemberAccessExprSyntax(
                                                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error"))),
                                                period: .periodToken(),
                                                declName: DeclReferenceExprSyntax(baseName: .identifier("error"))
                                            )),
                                            trailingComma: .commaToken()
                                        ),
                                        LabeledExprSyntax(
                                            label: .identifier("message"),
                                            colon: .colonToken(),
                                            expression: ExprSyntax(MemberAccessExprSyntax(
                                                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error"))),
                                                period: .periodToken(),
                                                declName: DeclReferenceExprSyntax(baseName: .identifier("message"))
                                            ))
                                        ),
                                    ]),
                                    rightParen: .rightParenToken(),
                                    additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                )
                            }
                            )),
                        ])
                    )
                }
            }

            VariableDeclSyntax(
                leadingTrivia: .newlines(2),
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("error"))),
                        typeAnnotation: TypeAnnotationSyntax(
                            colon: .colonToken(),
                            type: OptionalTypeSyntax(
                                wrappedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                                questionMark: .postfixQuestionMarkToken()
                            )
                        ),
                        accessorBlock: AccessorBlockSyntax(
                            leftBrace: .leftBraceToken(),
                            accessors: AccessorBlockSyntax.Accessors(CodeBlockItemListSyntax([
                                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(
                                    SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
                                        for error in errors {
                                            SwitchCaseSyntax(
                                                label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                                                    caseKeyword: .keyword(.case),
                                                    caseItems: SwitchCaseItemListSyntax([
                                                        SwitchCaseItemSyntax(pattern: PatternSyntax(ExpressionPatternSyntax(expression: ExprSyntax(MemberAccessExprSyntax(
                                                            period: .periodToken(),
                                                            declName: DeclReferenceExprSyntax(baseName: .identifier(error.name.camelCased()))
                                                        ))))),
                                                    ]),
                                                    colon: .colonToken()
                                                )),
                                                statements: CodeBlockItemListSyntax([
                                                    CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ReturnStmtSyntax(
                                                        returnKeyword: .keyword(.return),
                                                        expression: StringLiteralExprSyntax(content: error.name)
                                                    )
                                                    )),
                                                ])
                                            )
                                        }
                                        SwitchCaseSyntax(
                                            label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                                                caseKeyword: .keyword(.case),
                                                caseItems: SwitchCaseItemListSyntax([
                                                    SwitchCaseItemSyntax(pattern: PatternSyntax(ValueBindingPatternSyntax(
                                                        bindingSpecifier: .keyword(.let),
                                                        pattern: PatternSyntax(ExpressionPatternSyntax(expression: ExprSyntax(FunctionCallExprSyntax(
                                                            calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                                period: .periodToken(),
                                                                declName: DeclReferenceExprSyntax(baseName: .identifier("unexpected"))
                                                            )),
                                                            leftParen: .leftParenToken(),
                                                            arguments: LabeledExprListSyntax([
                                                                LabeledExprSyntax(
                                                                    expression: ExprSyntax(PatternExprSyntax(pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("error"))))),
                                                                    trailingComma: .commaToken()
                                                                ),
                                                                LabeledExprSyntax(expression: ExprSyntax(DiscardAssignmentExprSyntax(wildcard: .wildcardToken()))),
                                                            ]),
                                                            rightParen: .rightParenToken(),
                                                            additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                                        ))))
                                                    ))),
                                                ]),
                                                colon: .colonToken()
                                            )),
                                            statements: CodeBlockItemListSyntax([
                                                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ReturnStmtSyntax(
                                                    returnKeyword: .keyword(.return),
                                                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("error")))
                                                ))),
                                            ])
                                        )
                                    }
                                )),
                            ])),
                            rightBrace: .rightBraceToken()
                        )
                    ),
                ])
            )

            VariableDeclSyntax(
                leadingTrivia: .newlines(2),
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("message"))),
                        typeAnnotation: TypeAnnotationSyntax(
                            colon: .colonToken(),
                            type: OptionalTypeSyntax(
                                wrappedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                                questionMark: .postfixQuestionMarkToken()
                            )
                        ),
                        accessorBlock: AccessorBlockSyntax(
                            leftBrace: .leftBraceToken(),
                            accessors: AccessorBlockSyntax.Accessors(CodeBlockItemListSyntax([
                                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(
                                    SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
                                        for error in errors {
                                            SwitchCaseSyntax(
                                                label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                                                    caseKeyword: .keyword(.case),
                                                    caseItems: SwitchCaseItemListSyntax([
                                                        SwitchCaseItemSyntax(pattern: PatternSyntax(ValueBindingPatternSyntax(
                                                            bindingSpecifier: .keyword(.let),
                                                            pattern: PatternSyntax(ExpressionPatternSyntax(expression: ExprSyntax(FunctionCallExprSyntax(
                                                                calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                                    period: .periodToken(),
                                                                    declName: DeclReferenceExprSyntax(baseName: .identifier(error.name.camelCased()))
                                                                )),
                                                                leftParen: .leftParenToken(),
                                                                arguments: LabeledExprListSyntax([
                                                                    LabeledExprSyntax(expression: ExprSyntax(PatternExprSyntax(pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("message")))))),
                                                                ]),
                                                                rightParen: .rightParenToken(),
                                                                additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                                            ))))
                                                        ))),
                                                    ]),
                                                    colon: .colonToken()
                                                )),
                                                statements: CodeBlockItemListSyntax([
                                                    CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ReturnStmtSyntax(
                                                        returnKeyword: .keyword(.return),
                                                        expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("message")))
                                                    )
                                                    )),
                                                ])
                                            )
                                        }
                                        SwitchCaseSyntax(
                                            label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                                                caseKeyword: .keyword(.case),
                                                caseItems: SwitchCaseItemListSyntax([
                                                    SwitchCaseItemSyntax(pattern: PatternSyntax(ValueBindingPatternSyntax(
                                                        bindingSpecifier: .keyword(.let),
                                                        pattern: PatternSyntax(ExpressionPatternSyntax(expression: ExprSyntax(FunctionCallExprSyntax(
                                                            calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                                period: .periodToken(),
                                                                declName: DeclReferenceExprSyntax(baseName: .identifier("unexpected"))
                                                            )),
                                                            leftParen: .leftParenToken(),
                                                            arguments: LabeledExprListSyntax([
                                                                LabeledExprSyntax(expression: ExprSyntax(DiscardAssignmentExprSyntax(wildcard: .wildcardToken())),
                                                                                  trailingComma: .commaToken()),
                                                                LabeledExprSyntax(
                                                                    expression: ExprSyntax(PatternExprSyntax(pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("message")))))
                                                                ),
                                                            ]),
                                                            rightParen: .rightParenToken(),
                                                            additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                                        ))))
                                                    ))),
                                                ]),
                                                colon: .colonToken()
                                            )),
                                            statements: CodeBlockItemListSyntax([
                                                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ReturnStmtSyntax(
                                                    returnKeyword: .keyword(.return),
                                                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("message")))
                                                ))),
                                            ])
                                        )
                                    }
                                )),
                            ])),
                            rightBrace: .rightBraceToken()
                        )
                    ),
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

    static func typeNameForField(name: String, k: String, v: TypeSchema, defMap: ExtDefMap, isRequired: Bool = true, dropPrefix: Bool = true) -> String {
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
                let (_, tn) = v.namesFromRef(ref: def.ref, defMap: defMap, dropPrefix: dropPrefix)
                return tn
            case let .array(def):
                let ts = TypeSchema(id: v.id, prefix: v.prefix, defName: "Elem", type: def.items)
                let subt = Self.typeNameForField(name: "\(name)_\(k.titleCased())", k: "Elem", v: ts, defMap: defMap, dropPrefix: dropPrefix)
                return "[\(subt)]"
            case .union:
                if !dropPrefix {
                    return "\(Lex.structNameFor(prefix: v.prefix)).\(name)_\(k.titleCased())"
                } else {
                    return "\(name)_\(k.titleCased())"
                }
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
            "other"
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
            DoStmtSyntax(
                body: CodeBlockSyntax(statementsBuilder: {
                    ReturnStmtSyntax(
                        returnKeyword: .keyword(.return),
                        expression: TryExprSyntax(expression:
                            AwaitExprSyntax(expression: FunctionCallExprSyntax(
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
                            )
                        )
                    )
                }),
                catchClauses: [
                    CatchClauseSyntax(
                        CatchItemListSyntax {
                            CatchItemSyntax(pattern: ValueBindingPatternSyntax(
                                bindingSpecifier: .keyword(.let),
                                pattern: ExpressionPatternSyntax(
                                    expression: SequenceExprSyntax {
                                        PatternExprSyntax(
                                            pattern: IdentifierPatternSyntax(identifier: .identifier("error"))
                                        )
                                        UnresolvedAsExprSyntax()
                                        TypeExprSyntax(type: IdentifierTypeSyntax(name: "UnExpectedError"))
                                    }
                                )
                            )
                            )
                        }
                    ) {
                        ThrowStmtSyntax(expression: ExprSyntax("\(raw: typeName)_Error(error: error)"))
                    },
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
            let ts = TypeSchema(id: id, prefix: prefix, defName: key, type: property)
            let isRequired = required[key] ?? false
            let tname = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, isRequired: isRequired, dropPrefix: dropPrefix)
            let comma: TokenSyntax? = i == count ? nil : .commaToken()
            parameters.append(.init(firstName: .identifier(key), type: TypeSyntax(stringLiteral: tname), trailingComma: comma))
        }

        return parameters
    }

    func lex(leadingTrivia: Trivia? = nil, name: String, type typeName: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
        switch type {
        case let .string(def):
            if let knownValues = def.knownValues {
                genCodeStringWithKnownValues(def: def, leadingTrivia: leadingTrivia, name: name, knownValues: knownValues)
            } else if let cases = def.enum {
                genCodeStringWithEnum(def: def, leadingTrivia: leadingTrivia, name: name, cases: cases)
            } else {
                fatalError()
            }
        case let .object(def):
            genCodeObject(def: def, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
        case let .union(def):
            genCodeUnion(def: def, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
        case let .array(def):
            genCodeArray(def: def, leadingTrivia: leadingTrivia, name: name, type: typeName, defMap: defMap)
        default:
            fatalError()
        }
    }

    private func genCodeStringWithEnum(def _: StringTypeDefinition, leadingTrivia _: Trivia? = nil, name: String, cases: [String]) -> DeclSyntaxProtocol {
        var blocks = [MemberBlockItemSyntax]()
        for value in cases {
            let isKeyword = isNeedEscapingKeyword(value)
            blocks.append(MemberBlockItemSyntax(decl: EnumCaseDeclSyntax(
                caseKeyword: .keyword(.case),
                elements: EnumCaseElementListSyntax([
                    EnumCaseElementSyntax(
                        name: .identifier(isKeyword ? "`\(value.camelCased())`" : value.camelCased()),
                        rawValue: InitializerClauseSyntax(
                            equal: .equalToken(),
                            value: ExprSyntax(StringLiteralExprSyntax(
                                openingQuote: .stringQuoteToken(),
                                segments: StringLiteralSegmentListSyntax([
                                    StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(value))),
                                ]),
                                closingQuote: .stringQuoteToken()
                            ))
                        )
                    ),
                ])
            )))
        }
        blocks.append(contentsOf: [
            MemberBlockItemSyntax(decl: InitializerDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                initKeyword: .keyword(.`init`),
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax(
                        leftParen: .leftParenToken(),
                        parameters: FunctionParameterListSyntax([
                            FunctionParameterSyntax(
                                firstName: .identifier("from"),
                                secondName: .identifier("decoder"),
                                colon: .colonToken(),
                                type: TypeSyntax(SomeOrAnyTypeSyntax(
                                    someOrAnySpecifier: .keyword(.any),
                                    constraint: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Decoder")))
                                ))
                            ),
                        ]),
                        rightParen: .rightParenToken()
                    ),
                    effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                ),
                body: CodeBlockSyntax(
                    leftBrace: .leftBraceToken(),
                    statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(VariableDeclSyntax(
                            bindingSpecifier: .keyword(.let),
                            bindings: PatternBindingListSyntax([
                                PatternBindingSyntax(
                                    pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("container"))),
                                    initializer: InitializerClauseSyntax(
                                        equal: .equalToken(),
                                        value: ExprSyntax(TryExprSyntax(
                                            tryKeyword: .keyword(.try),
                                            expression: ExprSyntax(FunctionCallExprSyntax(
                                                calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("decoder"))),
                                                    period: .periodToken(),
                                                    declName: DeclReferenceExprSyntax(baseName: .identifier("singleValueContainer"))
                                                )),
                                                leftParen: .leftParenToken(),
                                                arguments: LabeledExprListSyntax([]),
                                                rightParen: .rightParenToken(),
                                                additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                            ))
                                        ))
                                    )
                                ),
                            ])
                        ))),
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(VariableDeclSyntax(
                            bindingSpecifier: .keyword(.let),
                            bindings: PatternBindingListSyntax([
                                PatternBindingSyntax(
                                    pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("rawValue"))),
                                    initializer: InitializerClauseSyntax(
                                        equal: .equalToken(),
                                        value: ExprSyntax(TryExprSyntax(
                                            tryKeyword: .keyword(.try),
                                            expression: ExprSyntax(FunctionCallExprSyntax(
                                                calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                                                    period: .periodToken(),
                                                    declName: DeclReferenceExprSyntax(baseName: .identifier("decode"))
                                                )),
                                                leftParen: .leftParenToken(),
                                                arguments: LabeledExprListSyntax([
                                                    LabeledExprSyntax(expression: ExprSyntax(MemberAccessExprSyntax(
                                                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("String"))),
                                                        period: .periodToken(),
                                                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                                                    ))),
                                                ]),
                                                rightParen: .rightParenToken(),
                                                additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                            ))
                                        ))
                                    )
                                ),
                            ])
                        ))),
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(GuardStmtSyntax(
                            guardKeyword: .keyword(.guard),
                            conditions: ConditionElementListSyntax([
                                ConditionElementSyntax(condition: ConditionElementSyntax.Condition(OptionalBindingConditionSyntax(
                                    bindingSpecifier: .keyword(.let),
                                    pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("value"))),
                                    initializer: InitializerClauseSyntax(
                                        equal: .equalToken(),
                                        value: ExprSyntax(FunctionCallExprSyntax(
                                            calledExpression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.Self))),
                                            leftParen: .leftParenToken(),
                                            arguments: LabeledExprListSyntax([
                                                LabeledExprSyntax(
                                                    label: .identifier("rawValue"),
                                                    colon: .colonToken(),
                                                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                                                ),
                                            ]),
                                            rightParen: .rightParenToken(),
                                            additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                        ))
                                    )
                                ))),
                            ]),
                            elseKeyword: .keyword(.else),
                            body: CodeBlockSyntax(
                                leftBrace: .leftBraceToken(),
                                statements: CodeBlockItemListSyntax([
                                    CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ThrowStmtSyntax(
                                        throwKeyword: .keyword(.throw),
                                        expression: ExprSyntax(FunctionCallExprSyntax(
                                            calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("DecodingError"))),
                                                period: .periodToken(),
                                                declName: DeclReferenceExprSyntax(baseName: .identifier("dataCorrupted"))
                                            )),
                                            leftParen: .leftParenToken(),
                                            arguments: LabeledExprListSyntax([
                                                LabeledExprSyntax(expression: ExprSyntax(FunctionCallExprSyntax(
                                                    calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                                        period: .periodToken(),
                                                        declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
                                                    )),
                                                    leftParen: .leftParenToken(),
                                                    arguments: LabeledExprListSyntax([
                                                        LabeledExprSyntax(
                                                            label: .identifier("codingPath"),
                                                            colon: .colonToken(),
                                                            expression: ExprSyntax(MemberAccessExprSyntax(
                                                                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                                                                period: .periodToken(),
                                                                declName: DeclReferenceExprSyntax(baseName: .identifier("codingPath"))
                                                            )),
                                                            trailingComma: .commaToken()
                                                        ),
                                                        LabeledExprSyntax(
                                                            label: .identifier("debugDescription"),
                                                            colon: .colonToken(),
                                                            expression: ExprSyntax(StringLiteralExprSyntax(
                                                                openingQuote: .stringQuoteToken(),
                                                                segments: StringLiteralSegmentListSyntax([
                                                                    StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment("invalid rawValue: "))),
                                                                    StringLiteralSegmentListSyntax.Element(ExpressionSegmentSyntax(
                                                                        backslash: .backslashToken(),
                                                                        leftParen: .leftParenToken(),
                                                                        expressions: LabeledExprListSyntax([
                                                                            LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue")))),
                                                                        ]),
                                                                        rightParen: .rightParenToken()
                                                                    )),
                                                                    StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(""))),
                                                                ]),
                                                                closingQuote: .stringQuoteToken()
                                                            ))
                                                        ),
                                                    ]),
                                                    rightParen: .rightParenToken(),
                                                    additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                                ))),
                                            ]),
                                            rightParen: .rightParenToken(),
                                            additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                        ))
                                    ))),
                                ]),
                                rightBrace: .rightBraceToken()
                            )
                        ))),
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(SequenceExprSyntax(elements: ExprListSyntax([
                            ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                            ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                            ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("value"))),
                        ])))),
                    ]),
                    rightBrace: .rightBraceToken()
                )
            )),
            MemberBlockItemSyntax(decl: FunctionDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                funcKeyword: .keyword(.func),
                name: .identifier("encode"),
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax(
                        leftParen: .leftParenToken(),
                        parameters: FunctionParameterListSyntax([
                            FunctionParameterSyntax(
                                firstName: .identifier("to"),
                                secondName: .identifier("encoder"),
                                colon: .colonToken(),
                                type: TypeSyntax(SomeOrAnyTypeSyntax(
                                    someOrAnySpecifier: .keyword(.any),
                                    constraint: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Encoder")))
                                ))
                            ),
                        ]),
                        rightParen: .rightParenToken()
                    ),
                    effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                ),
                body: CodeBlockSyntax(
                    leftBrace: .leftBraceToken(),
                    statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(TryExprSyntax(
                            tryKeyword: .keyword(.try),
                            expression: ExprSyntax(FunctionCallExprSyntax(
                                calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue"))),
                                    period: .periodToken(),
                                    declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                                )),
                                leftParen: .leftParenToken(),
                                arguments: LabeledExprListSyntax([
                                    LabeledExprSyntax(
                                        label: .identifier("to"),
                                        colon: .colonToken(),
                                        expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("encoder")))
                                    ),
                                ]),
                                rightParen: .rightParenToken(),
                                additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                            ))
                        ))),
                    ]),
                    rightBrace: .rightBraceToken()
                )
            )),
        ])
        return DeclSyntax(EnumDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.indirect)),
            ]),
            enumKeyword: .keyword(.enum),
            name: .identifier(name),
            inheritanceClause: InheritanceClauseSyntax(
                colon: .colonToken(),
                inheritedTypes: InheritedTypeListSyntax([
                    InheritedTypeSyntax(
                        type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String"))),
                        trailingComma: .commaToken()
                    ),
                    InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable")))),
                ])
            ),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: MemberBlockItemListSyntax(blocks),
                rightBrace: .rightBraceToken()
            )
        ))
    }

    private func genCodeStringWithKnownValues(def _: StringTypeDefinition, leadingTrivia: Trivia? = nil, name: String, knownValues: [String]) -> DeclSyntaxProtocol {
        var initCases = [SwitchCaseListSyntax.Element]()
        var rawValueCases = [SwitchCaseListSyntax.Element]()
        var blocks = [MemberBlockItemSyntax]()
        blocks.append(MemberBlockItemSyntax(decl: TypeAliasDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
            ]),
            typealiasKeyword: .keyword(.typealias),
            name: .identifier("RawValue"),
            initializer: TypeInitializerClauseSyntax(
                equal: .equalToken(),
                value: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
            ),
            trailingTrivia: .newlines(2)
        )))
        for value in knownValues {
            let isKeyword = isNeedEscapingKeyword(value)
            initCases.append(SwitchCaseListSyntax.Element(SwitchCaseSyntax(
                label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                    caseKeyword: .keyword(.case),
                    caseItems: SwitchCaseItemListSyntax([
                        SwitchCaseItemSyntax(pattern: PatternSyntax(ExpressionPatternSyntax(expression: ExprSyntax(StringLiteralExprSyntax(
                            openingQuote: .stringQuoteToken(),
                            segments: StringLiteralSegmentListSyntax([
                                StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(value))),
                            ]),
                            closingQuote: .stringQuoteToken()
                        ))))),
                    ]),
                    colon: .colonToken()
                )),
                statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(SequenceExprSyntax(elements: ExprListSyntax([
                        ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                        ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                        ExprSyntax(MemberAccessExprSyntax(
                            period: .periodToken(),
                            declName: DeclReferenceExprSyntax(baseName: .identifier(isKeyword ? "`\(value.camelCased())`" : value.camelCased()))
                        )),
                    ])))),
                ])
            )))

            rawValueCases.append(SwitchCaseListSyntax.Element(SwitchCaseSyntax(
                label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                    caseKeyword: .keyword(.case),
                    caseItems: SwitchCaseItemListSyntax([
                        SwitchCaseItemSyntax(pattern: PatternSyntax(ExpressionPatternSyntax(expression: ExprSyntax(MemberAccessExprSyntax(
                            period: .periodToken(),
                            declName: DeclReferenceExprSyntax(baseName: .identifier(value.camelCased()))
                        ))))),
                    ]),
                    colon: .colonToken()
                )),
                statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(StringLiteralExprSyntax(
                        openingQuote: .stringQuoteToken(),
                        segments: StringLiteralSegmentListSyntax([
                            StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(value))),
                        ]),
                        closingQuote: .stringQuoteToken()
                    ))),
                ])
            )))

            blocks.append(MemberBlockItemSyntax(decl: EnumCaseDeclSyntax(
                caseKeyword: .keyword(.case),
                elements: EnumCaseElementListSyntax([
                    EnumCaseElementSyntax(name: .identifier(value.camelCased())),
                ])
            )))
        }
        initCases.append(SwitchCaseListSyntax.Element(SwitchCaseSyntax(
            label: SwitchCaseSyntax.Label(SwitchDefaultLabelSyntax(
                defaultKeyword: .keyword(.default),
                colon: .colonToken()
            )),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(SequenceExprSyntax(elements: ExprListSyntax([
                    ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                    ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                    ExprSyntax(FunctionCallExprSyntax(
                        calledExpression: ExprSyntax(MemberAccessExprSyntax(
                            period: .periodToken(),
                            declName: DeclReferenceExprSyntax(baseName: .identifier("other"))
                        )),
                        leftParen: .leftParenToken(),
                        arguments: LabeledExprListSyntax([
                            LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue")))),
                        ]),
                        rightParen: .rightParenToken()
                    )),
                ])))),
            ])
        )))

        rawValueCases.append(SwitchCaseListSyntax.Element(SwitchCaseSyntax(
            label: SwitchCaseSyntax.Label(SwitchCaseLabelSyntax(
                caseKeyword: .keyword(.case),
                caseItems: SwitchCaseItemListSyntax([
                    SwitchCaseItemSyntax(pattern: PatternSyntax(ValueBindingPatternSyntax(
                        bindingSpecifier: .keyword(.let),
                        pattern: PatternSyntax(ExpressionPatternSyntax(expression: FunctionCallExprSyntax(
                            calledExpression: MemberAccessExprSyntax(
                                period: .periodToken(),
                                declName: DeclReferenceExprSyntax(baseName: .identifier("other"))
                            ),
                            leftParen: .leftParenToken(),
                            arguments: LabeledExprListSyntax([
                                LabeledExprSyntax(expression: PatternExprSyntax(pattern: PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("value"))))),
                            ]),
                            rightParen: .rightParenToken()
                        )))
                    ))),
                ]),
                colon: .colonToken()
            )),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(DeclReferenceExprSyntax(baseName: .identifier("value")))),
            ])
        )))

        blocks.append(contentsOf: [MemberBlockItemSyntax(decl: EnumCaseDeclSyntax(
                caseKeyword: .keyword(.case),
                elements: EnumCaseElementListSyntax([
                    EnumCaseElementSyntax(
                        name: .identifier("other"),
                        parameterClause: EnumCaseParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: EnumCaseParameterListSyntax([
                                EnumCaseParameterSyntax(
                                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
                                ),
                            ]),
                            rightParen: .rightParenToken()
                        )
                    ),
                ])
            )),
            MemberBlockItemSyntax(decl: InitializerDeclSyntax(
                leadingTrivia: .newlines(2),
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                initKeyword: .keyword(.`init`),
                optionalMark: .postfixQuestionMarkToken(),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(
                    leftParen: .leftParenToken(),
                    parameters: FunctionParameterListSyntax([
                        FunctionParameterSyntax(
                            firstName: .identifier("rawValue"),
                            colon: .colonToken(),
                            type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
                        ),
                    ]),
                    rightParen: .rightParenToken()
                )),
                body: CodeBlockSyntax(
                    leftBrace: .leftBraceToken(),
                    statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ExpressionStmtSyntax(expression: SwitchExprSyntax(
                            switchKeyword: .keyword(.switch),
                            subject: DeclReferenceExprSyntax(baseName: .identifier("rawValue")),
                            leftBrace: .leftBraceToken(),
                            cases: SwitchCaseListSyntax(initCases),
                            rightBrace: .rightBraceToken()
                        )))),
                    ]),
                    rightBrace: .rightBraceToken()
                )
            )),
            MemberBlockItemSyntax(decl: VariableDeclSyntax(
                leadingTrivia: .newlines(2),
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
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
                            leftBrace: .leftBraceToken(),
                            accessors: AccessorBlockSyntax.Accessors(CodeBlockItemListSyntax([
                                CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(ExpressionStmtSyntax(expression: SwitchExprSyntax(
                                    switchKeyword: .keyword(.switch),
                                    subject: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                                    leftBrace: .leftBraceToken(),
                                    cases: SwitchCaseListSyntax(rawValueCases),
                                    rightBrace: .rightBraceToken()
                                )))),
                            ])),
                            rightBrace: .rightBraceToken()
                        )
                    ),
                ])
            )),
            MemberBlockItemSyntax(decl: InitializerDeclSyntax(
                leadingTrivia: .newlines(2),
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                initKeyword: .keyword(.`init`),
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax(
                        leftParen: .leftParenToken(),
                        parameters: FunctionParameterListSyntax([
                            FunctionParameterSyntax(
                                firstName: .identifier("from"),
                                secondName: .identifier("decoder"),
                                colon: .colonToken(),
                                type: TypeSyntax(SomeOrAnyTypeSyntax(
                                    someOrAnySpecifier: .keyword(.any),
                                    constraint: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Decoder")))
                                ))
                            ),
                        ]),
                        rightParen: .rightParenToken()
                    ),
                    effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                ),
                body: CodeBlockSyntax(
                    leftBrace: .leftBraceToken(),
                    statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(VariableDeclSyntax(
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
                                                    ),
                                                ]),
                                                rightParen: .rightParenToken()
                                            )
                                        )
                                    )
                                ),
                            ])
                        ))),
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(SequenceExprSyntax(elements: ExprListSyntax([
                            ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                            ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                            ExprSyntax(ForceUnwrapExprSyntax(
                                expression: FunctionCallExprSyntax(
                                    calledExpression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.Self))),
                                    leftParen: .leftParenToken(),
                                    arguments: LabeledExprListSyntax([
                                        LabeledExprSyntax(
                                            label: .identifier("rawValue"),
                                            colon: .colonToken(),
                                            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("rawValue")))
                                        ),
                                    ]),
                                    rightParen: .rightParenToken()
                                ),
                                exclamationMark: .exclamationMarkToken()
                            )),
                        ])))),
                    ]),
                    rightBrace: .rightBraceToken()
                )
            )),
            MemberBlockItemSyntax(decl: FunctionDeclSyntax(
                leadingTrivia: .newlines(2),
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public)),
                ]),
                funcKeyword: .keyword(.func),
                name: .identifier("encode"),
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax(
                        leftParen: .leftParenToken(),
                        parameters: FunctionParameterListSyntax([
                            FunctionParameterSyntax(
                                firstName: .identifier("to"),
                                secondName: .identifier("encoder"),
                                colon: .colonToken(),
                                type: TypeSyntax(SomeOrAnyTypeSyntax(
                                    someOrAnySpecifier: .keyword(.any),
                                    constraint: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Encoder")))
                                ))
                            ),
                        ]),
                        rightParen: .rightParenToken()
                    ),
                    effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                ),
                body: CodeBlockSyntax(
                    leftBrace: .leftBraceToken(),
                    statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(TryExprSyntax(
                            tryKeyword: .keyword(.try),
                            expression: FunctionCallExprSyntax(
                                calledExpression: ExprSyntax(MemberAccessExprSyntax(
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
                                    ),
                                ]),
                                rightParen: .rightParenToken()
                            )
                        ))),
                    ]),
                    rightBrace: .rightBraceToken()
                )
            ))])
        return EnumDeclSyntax(
            leadingTrivia: leadingTrivia,
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.indirect)),
            ]),
            enumKeyword: .keyword(.enum),
            name: .identifier(name),
            inheritanceClause: InheritanceClauseSyntax(
                colon: .colonToken(),
                inheritedTypes: InheritedTypeListSyntax([
                    InheritedTypeSyntax(
                        type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("RawRepresentable"))),
                        trailingComma: .commaToken()
                    ),
                    InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable")))),
                ])
            ),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: MemberBlockItemListSyntax(blocks),
                rightBrace: .rightBraceToken()
            )
        )
    }

    private func genCodeObject(def: ObjectTypeDefinition, leadingTrivia: Trivia? = nil, name: String, type typeName: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
        var required = [String: Bool]()
        for req in def.required ?? [] {
            required[req] = true
        }

        for key in def.nullable ?? [] {
            required[key] = false
        }
        let DeclSyntaxType: any ExtendedDeclSyntax.Type = isRecord ? ClassDeclSyntax.self : StructDeclSyntax.self
        return DeclSyntaxType.init(
            leadingTrivia: leadingTrivia,
            modifiers: [
                DeclModifierSyntax(name: .keyword(.public)),
            ],
            typeKeyword: isRecord ? .keyword(.class) : .keyword(.struct),
            name: .init(stringLiteral: isRecord ? "\(Lex.structNameFor(prefix: prefix))_\(name)" : name),
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
                let tname = Self.typeNameForField(name: name, k: key, v: ts, defMap: defMap, isRequired: isRequired, dropPrefix: !isRecord)
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
                            initializerParameters(name: name, def: def, required: required, defMap: defMap, dropPrefix: !isRecord)),
                        rightParen: .rightParenToken()
                    )
                )
            ) {
                for (key, _) in def.sortedProperties {
                    SequenceExprSyntax(elements: ExprListSyntax([
                        ExprSyntax(MemberAccessExprSyntax(
                            base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                            period: .periodToken(),
                            declName: DeclReferenceExprSyntax(baseName: .identifier(key))
                        )),
                        ExprSyntax(AssignmentExprSyntax(equal: .equalToken())),
                        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(key))),
                    ]))
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
    }

    private func genCodeUnion(def: UnionTypeDefinition, leadingTrivia: Trivia? = nil, name: String, type _: String, defMap: ExtDefMap) -> DeclSyntaxProtocol {
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
                DeclModifierSyntax(name: .keyword(.indirect)),
            ],
            name: .init(stringLiteral: name),
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "Codable"))
            }
        ) {
            for ts in tss {
                let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
                let tn: TypeSyntaxProtocol = ts.prefix == prefix ? IdentifierTypeSyntax(name: .identifier(ts.typeName)) : MemberTypeSyntax(
                    baseType: IdentifierTypeSyntax(name: .identifier(Lex.structNameFor(prefix: ts.prefix))),
                    period: .periodToken(),
                    name: .identifier(ts.typeName)
                )

                EnumCaseDeclSyntax(
                    caseKeyword: .keyword(.case),
                    elements: EnumCaseElementListSyntax([
                        EnumCaseElementSyntax(
                            name: .identifier(Lex.caseNameFromId(id: id, prefix: prefix)),
                            parameterClause: EnumCaseParameterClauseSyntax(
                                leftParen: .leftParenToken(),
                                parameters: EnumCaseParameterListSyntax([
                                    EnumCaseParameterSyntax(type: tn),
                                ]),
                                rightParen: .rightParenToken()
                            )
                        ),
                    ])
                )
            }

            EnumCaseDeclSyntax(
                caseKeyword: .keyword(.case),
                elements: EnumCaseElementListSyntax([
                    EnumCaseElementSyntax(
                        name: .identifier("other"),
                        parameterClause: EnumCaseParameterClauseSyntax(
                            leftParen: .leftParenToken(),
                            parameters: EnumCaseParameterListSyntax([
                                EnumCaseParameterSyntax(stringLiteral: "UnknownRecord"),
                            ]),
                            rightParen: .rightParenToken()
                        )
                    ),
                ])
            )
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
                VariableDeclSyntax(
                    bindingSpecifier: .keyword(.let)
                ) {
                    PatternBindingSyntax(
                        pattern: PatternSyntax(stringLiteral: "container"),
                        initializer: InitializerClauseSyntax(
                            value: TryExprSyntax(expression: FunctionCallExprSyntax(
                                calledExpression: MemberAccessExprSyntax(
                                    base: DeclReferenceExprSyntax(baseName: .identifier("decoder")),
                                    name: .identifier("container")
                                ),
                                leftParen: .leftParenToken(),
                                arguments: .init([
                                    LabeledExprSyntax(label: "keyedBy", colon: .colonToken(), expression: MemberAccessExprSyntax(
                                        base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                                        name: .keyword(.self)
                                    )),
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
                            value: TryExprSyntax(expression: FunctionCallExprSyntax(
                                calledExpression: MemberAccessExprSyntax(
                                    base: DeclReferenceExprSyntax(baseName: .identifier("container")),
                                    name: .identifier("decode")
                                ),
                                leftParen: .leftParenToken(),
                                arguments: .init([
                                    LabeledExprSyntax(expression: MemberAccessExprSyntax(
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
                        SwitchCaseSyntax(label: .case(
                            .init(caseItems: [
                                .init(pattern: ExpressionPatternSyntax(expression: StringLiteralExprSyntax(content: id))),
                            ])
                        )) {
                            SequenceExprSyntax {
                                DeclReferenceExprSyntax(baseName: .keyword(.self))
                                AssignmentExprSyntax()
                                TryExprSyntax(expression: FunctionCallExprSyntax(
                                    calledExpression: MemberAccessExprSyntax(
                                        name: .identifier(Lex.caseNameFromId(id: id, prefix: prefix))
                                    ),
                                    leftParen: .leftParenToken(),
                                    arguments: .init([
                                        LabeledExprSyntax(expression: FunctionCallExprSyntax(
                                            calledExpression: MemberAccessExprSyntax(
                                                name: .keyword(.`init`)
                                            ),
                                            leftParen: .leftParenToken(),
                                            arguments: .init([
                                                LabeledExprSyntax(label: "from", colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("decoder"))),
                                            ]),
                                            rightParen: .rightParenToken()
                                        )),
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
                            TryExprSyntax(expression: FunctionCallExprSyntax(
                                calledExpression: ExprSyntax(".other"),
                                leftParen: .leftParenToken(),
                                arguments: .init([
                                    LabeledExprSyntax(expression: FunctionCallExprSyntax(
                                        calledExpression: ExprSyntax(".init"),
                                        leftParen: .leftParenToken(),
                                        arguments: .init([
                                            LabeledExprSyntax(label: "from", colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: .identifier("decoder"))),
                                        ]),
                                        rightParen: .rightParenToken()
                                    )),
                                ]),
                                rightParen: .rightParenToken()
                            )
                            )
                        }
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
                            .init(firstName: .identifier("to"), secondName: .identifier("encoder"), type: TypeSyntax("Encoder")),
                        ]),
                        rightParen: .rightParenToken()
                    ),
                    effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws))
                )
            ) {
                VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var)
                ) {
                    PatternBindingSyntax(
                        pattern: PatternSyntax(stringLiteral: "container"),
                        initializer: InitializerClauseSyntax(
                            value: FunctionCallExprSyntax(
                                calledExpression: MemberAccessExprSyntax(
                                    base: DeclReferenceExprSyntax(baseName: .identifier("encoder")),
                                    name: .identifier("container")
                                ),
                                leftParen: .leftParenToken(),
                                arguments: .init([
                                    LabeledExprSyntax(label: "keyedBy", colon: .colonToken(), expression: MemberAccessExprSyntax(
                                        base: DeclReferenceExprSyntax(baseName: .identifier("CodingKeys")),
                                        name: .keyword(.self)
                                    )),
                                ]),
                                rightParen: .rightParenToken()
                            )
                        )
                    )
                }

                SwitchExprSyntax(subject: DeclReferenceExprSyntax(baseName: .keyword(.self))) {
                    for ts in tss {
                        let id = ts.defName == "main" ? ts.id : #"\#(ts.id)#\#(ts.defName)"#
                        SwitchCaseSyntax(label: .case(
                            .init(caseItems: [
                                .init(pattern: ValueBindingPatternSyntax(
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
                                                ),
                                            ]),
                                            rightParen: .rightParenToken()
                                        )
                                    )
                                )),
                            ])
                        )) {
                            TryExprSyntax(
                                tryKeyword: .keyword(.try),
                                expression: ExprSyntax(FunctionCallExprSyntax(
                                    calledExpression: ExprSyntax(MemberAccessExprSyntax(
                                        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                                        period: .periodToken(),
                                        declName: DeclReferenceExprSyntax(baseName: .identifier("encode"))
                                    )),
                                    leftParen: .leftParenToken(),
                                    arguments: LabeledExprListSyntax([
                                        LabeledExprSyntax(
                                            expression: ExprSyntax(StringLiteralExprSyntax(
                                                openingQuote: .stringQuoteToken(),
                                                segments: StringLiteralSegmentListSyntax([
                                                    StringLiteralSegmentListSyntax.Element(StringSegmentSyntax(content: .stringSegment(id))),
                                                ]),
                                                closingQuote: .stringQuoteToken()
                                            )),
                                            trailingComma: .commaToken()
                                        ),
                                        LabeledExprSyntax(
                                            label: .identifier("forKey"),
                                            colon: .colonToken(),
                                            expression: ExprSyntax(MemberAccessExprSyntax(
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
                                expression: ExprSyntax(FunctionCallExprSyntax(
                                    calledExpression: ExprSyntax(MemberAccessExprSyntax(
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
                                        ),
                                    ]),
                                    rightParen: .rightParenToken(),
                                    additionalTrailingClosures: MultipleTrailingClosureElementListSyntax([])
                                ))
                            )
                        }
                    }
                    SwitchCaseSyntax(label: .case(
                        .init(caseItems: [
                            .init(pattern: ExpressionPatternSyntax(expression: MemberAccessExprSyntax(name: .identifier("other")))),
                        ])
                    )) {
                        StmtSyntax("break")
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

    var errors: [ErrorResponse]? {
        switch self {
        case let .procedure(t):
            t.errors
        case let .query(t):
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

struct UnionTypeDefinition: Codable {
    var type: FieldType { .union }
    let description: String?
    let refs: [String]
    let closed: Bool?
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
    var errors: [ErrorResponse]? { get }

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
                let isRequired = required[name] ?? false
                let tn: String
                if case let .string(def) = t, def.enum != nil || def.knownValues != nil {
                    tn = isRequired ? "\(fname)_\(name.titleCased())" : "\(fname)_\(name.titleCased())?"
                } else {
                    let ts = TypeSchema(id: ts.id, prefix: ts.prefix, defName: name, type: t)
                    tn = TypeSchema.typeNameForField(name: name, k: "", v: ts, defMap: defMap, isRequired: isRequired)
                }
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
            var required = [String: Bool]()
            for req in parameters.required ?? [] {
                required[req] = true
            }
            return DictionaryExprSyntax {
                for (name, t) in parameters.sortedProperties {
                    let ts = TypeSchema(id: id, prefix: prefix, defName: name, type: t)
                    let tn = TypeSchema.paramNameForField(typeSchema: ts)
                    let isRequired = required[name] ?? false
                    let stringLiteral = if case let .string(def) = t, def.enum != nil || def.knownValues != nil {
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
}

struct QueryTypeDefinition: HTTPAPITypeDefinition {
    var type: FieldType { .query }
    let parameters: Parameters?
    let output: OutputType?
    let input: InputType?
    let description: String?
    let errors: [ErrorResponse]?
}

struct SubscriptionDefinition: Codable {
    var type: FieldType {
        .subscription
    }

    let parameters: Parameters?
    let message: MessageType?
}

struct RecordDefinition: Codable {
    var type: FieldType {
        .record
    }

    let key: String
    let record: ObjectTypeDefinition
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

private protocol ExtendedDeclSyntax: DeclSyntaxProtocol {
    init(
        leadingTrivia: Trivia?,
        modifiers: DeclModifierListSyntax,
        typeKeyword: TokenSyntax,
        name: TokenSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        @MemberBlockItemListBuilder memberBlockBuilder: () throws -> MemberBlockItemListSyntax
    ) rethrows
}

extension StructDeclSyntax: ExtendedDeclSyntax {
    init(
        leadingTrivia: Trivia?,
        modifiers: DeclModifierListSyntax,
        typeKeyword: TokenSyntax = .keyword(.struct),
        name: TokenSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        @MemberBlockItemListBuilder memberBlockBuilder: () throws -> MemberBlockItemListSyntax
    ) rethrows {
        try self.init(leadingTrivia: leadingTrivia,
                      modifiers: modifiers,
                      structKeyword: typeKeyword,
                      name: name,
                      inheritanceClause: inheritanceClause,
                      memberBlockBuilder: memberBlockBuilder)
    }
}

extension ClassDeclSyntax: ExtendedDeclSyntax {
    init(
        leadingTrivia: Trivia?,
        modifiers: DeclModifierListSyntax,
        typeKeyword: TokenSyntax = .keyword(.class),
        name: TokenSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        @MemberBlockItemListBuilder memberBlockBuilder: () throws -> MemberBlockItemListSyntax
    ) rethrows {
        try self.init(leadingTrivia: leadingTrivia,
                      modifiers: modifiers,
                      classKeyword: typeKeyword,
                      name: name,
                      inheritanceClause: inheritanceClause,
                      memberBlockBuilder: memberBlockBuilder)
    }
}
