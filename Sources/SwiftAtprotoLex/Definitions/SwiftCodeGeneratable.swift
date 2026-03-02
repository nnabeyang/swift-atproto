import SwiftSyntax

protocol SwiftCodeGeneratable {
  func generateDeclaration(leadingTrivia: Trivia?, ts: TypeSchema, name: String, type typeName: String, defMap: ExtDefMap) -> any DeclSyntaxProtocol
}
