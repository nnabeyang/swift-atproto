#if os(macOS) || os(Linux)

  import Foundation
  import Testing

  @testable import SourceControl

  @Suite("Lexicon configuration")
  struct LexiconConfigTests {
    @Test("accessModifier defaults to public")
    func accessModifierDefaultsToPublic() throws {
      let config = try decodeConfig(
        """
        {"dependencies": []}
        """)

      #expect(config.accessModifier == .public)
    }

    @Test(
      "accessModifier accepts Swift access levels",
      arguments: [AccessModifier.internal, .package, .public])
    func accessModifierAcceptsSwiftAccessLevels(accessModifier: AccessModifier) throws {
      let config = try decodeConfig(
        """
        {"dependencies": [], "accessModifier": "\(accessModifier.rawValue)"}
        """)

      #expect(config.accessModifier == accessModifier)
    }

    private func decodeConfig(_ source: String) throws -> LexiconConfig {
      try JSONDecoder().decode(
        LexiconConfig.self,
        from: Data(source.utf8),
        configuration: nil)
    }
  }

#endif
