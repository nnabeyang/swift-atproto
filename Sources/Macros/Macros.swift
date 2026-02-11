//
//  Macros.swift
//  SwiftAtproto
//
//  Created by Noriaki Watanabe on 2024/12/23.
//

#if os(macOS) || os(Linux)
  import SwiftCompilerPlugin
  import SwiftDiagnostics
  import SwiftSyntax
  import SwiftSyntaxBuilder
  import SwiftSyntaxMacros

  public struct XRPCClientMacro {}

  extension XRPCClientMacro: MemberMacro {
    public static func expansion(
      of _: AttributeSyntax,
      providingMembersOf declaration: some DeclGroupSyntax,
      conformingTo _: [TypeSyntax],
      in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
      var parameters = [FunctionParameterSyntax]()
      var variables = [VariableDeclSyntax]()
      var codeblocks = [CodeBlockItemSyntax]()
      for member in declaration.memberBlock.members {
        guard let v = member.decl.as(VariableDeclSyntax.self),
          let binding = v.bindings.first,
          binding.accessorBlock == nil,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
          continue
        }
        guard name.identifier.trimmedDescription != "decoder" else { continue }
        variables.append(v)
      }
      let last = variables.count - 1
      for (i, decl) in variables.enumerated() {
        guard
          let binding = decl.bindings.first,
          let type = binding.typeAnnotation?.type,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)
        else { continue }
        parameters.append(
          FunctionParameterSyntax(
            firstName: name.identifier,
            colon: .colonToken(),
            type: type,
            trailingComma: i == last ? nil : .commaToken()
          ))
        codeblocks.append(
          CodeBlockItemSyntax(
            item: CodeBlockItemSyntax.Item(
              SequenceExprSyntax {
                MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: name.identifier)
                )
                AssignmentExprSyntax(equal: .equalToken())
                DeclReferenceExprSyntax(baseName: name.identifier)
              })))
      }
      codeblocks.append(
        CodeBlockItemSyntax(
          item: CodeBlockItemSyntax.Item(
            SequenceExprSyntax {
              DeclReferenceExprSyntax(baseName: .identifier("decoder"))
              AssignmentExprSyntax(equal: .equalToken())
              FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: .identifier("JSONDecoder")))
            }
          )))
      return [
        DeclSyntax(
          InitializerDeclSyntax(
            modifiers: DeclModifierListSyntax([
              DeclModifierSyntax(name: .keyword(.private))
            ]),
            signature: FunctionSignatureSyntax(
              parameterClause: FunctionParameterClauseSyntax {
                parameters
              }),
            body: CodeBlockSyntax {
              codeblocks
            }
          ))
      ]
    }
  }

  extension XRPCClientMacro: ExtensionMacro {
    public static func expansion(
      of _: AttributeSyntax,
      attachedTo _: some DeclGroupSyntax,
      providingExtensionsOf type: some TypeSyntaxProtocol,
      conformingTo _: [TypeSyntax],
      in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
      [
        ExtensionDeclSyntax(
          extensionKeyword: .keyword(.extension),
          extendedType: TypeSyntax(IdentifierTypeSyntax(name: .identifier(type.trimmedDescription))),
          inheritanceClause: InheritanceClauseSyntax(
            colon: .colonToken(),
            inheritedTypes: InheritedTypeListSyntax([
              InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("XRPCClientProtocol")))
            ])
          ),
          memberBlock: MemberBlockSyntax(
            leftBrace: .leftBraceToken(),
            members: MemberBlockItemListSyntax([]),
            rightBrace: .rightBraceToken()
          )
        )
      ]
    }
  }

  @main
  struct ATProtoMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
      XRPCClientMacro.self
    ]
  }
#endif
