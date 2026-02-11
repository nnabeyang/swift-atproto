import ArgumentParser
import Foundation

#if os(macOS) || os(Linux)
  import SourceControl
  import SwiftAtprotoLex
#endif

@main
struct Lexgen: AsyncParsableCommand {
  #if os(macOS) || os(Linux)
    static var configuration: CommandConfiguration {
      CommandConfiguration(commandName: "swift-atproto", version: SourceControl.version)
    }
  #endif
  #if os(macOS)
    private static let defaultModulePath = "Sources/Lexicon"

    @Option(name: .customLong("atproto-configuration"))
    var configuration: String
    @Option(name: .long)
    var outdir: String?
  #endif

  mutating func run() async throws {
    #if os(macOS)
      let configurationtURL = URL(filePath: configuration)
      let data = try Data(contentsOf: configurationtURL)
      let config = try JSONDecoder().decode(LexiconConfig.self, from: data)
      let module = outdir ?? config.module ?? Self.defaultModulePath
      let rootURL = configurationtURL.deletingLastPathComponent()
      try SourceControl.main(rootURL: rootURL, config: config, module: module)
      try await SwiftAtprotoLex.main(outdir: module, path: SourceControl.lexiconsDirectoryURL(packageRootURL: rootURL).path())
    #elseif os(Linux)
      print("swift-atproto lexgen is not supported on Linux yet.\n")
      print(Self.helpMessage())
    #endif
  }
}
