#if os(macOS) || os(Linux)
  import ArgumentParser
  import Foundation
  import SourceControl
  import SwiftAtprotoLex

  @main
  struct Lexgen: ParsableCommand {
    static var configuration: CommandConfiguration {
      CommandConfiguration(commandName: "swift-atproto", version: SourceControl.version)
    }
    #if os(macOS)
      private static let defaultModulePath = "Sources/Lexicon"

      @Option(name: .customLong("atproto-configuration"))
      var configuration: String
      @Option(name: .long)
      var outdir: String?
    #endif

    mutating func run() throws {
      #if os(macOS)
        let configurationtURL = URL(filePath: configuration)
        let data = try Data(contentsOf: configurationtURL)
        let config = try JSONDecoder().decode(LexiconConfig.self, from: data)
        let module = outdir ?? config.module ?? Self.defaultModulePath
        let rootURL = configurationtURL.deletingLastPathComponent()
        try SourceControl.main(rootURL: rootURL, config: config, module: module)
        try SwiftAtprotoLex.main(outdir: module, path: SourceControl.lexiconsDirectoryURL(packageRootURL: rootURL).path())
      #endif
    }
  }
#endif
