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

      for decl in variables {
        guard
          let binding = decl.bindings.first,
          let type = binding.typeAnnotation?.type,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)
        else { continue }
        parameters.append(
          FunctionParameterSyntax(
            firstName: name.identifier,
            colon: .colonToken(),
            type: type
          ))
      }
      return [
        DeclSyntax(
          InitializerDeclSyntax(
            modifiers: DeclModifierListSyntax([
              DeclModifierSyntax(name: .keyword(.private))
            ]),
            signature: FunctionSignatureSyntax(
              parameterClause: FunctionParameterClauseSyntax {
                parameters
              })
          ) {
            for parameter in parameters {
              SequenceExprSyntax {
                MemberAccessExprSyntax(
                  base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                  period: .periodToken(),
                  declName: DeclReferenceExprSyntax(baseName: parameter.firstName)
                )
                AssignmentExprSyntax(equal: .equalToken())
                DeclReferenceExprSyntax(baseName: parameter.firstName)
              }
            }
            SequenceExprSyntax {
              DeclReferenceExprSyntax(baseName: .identifier("decoder"))
              AssignmentExprSyntax(equal: .equalToken())
              FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: .identifier("JSONDecoder")))
            }
          }
        )
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
          inheritanceClause: InheritanceClauseSyntax {
            InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("_XRPCClientProtocol")))
          }
        ) {}
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
