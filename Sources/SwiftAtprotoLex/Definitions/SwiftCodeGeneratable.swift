import SwiftSyntax

#if os(macOS) || os(Linux)
  import SourceControl
#endif

protocol SwiftCodeGeneratable {
  func generateDeclaration(
    leadingTrivia: Trivia?, ts: TypeSchema, name: String, type typeName: String,
    defMap: ExtDefMap, generate: GenerateOption
  ) -> any DeclSyntaxProtocol
}
