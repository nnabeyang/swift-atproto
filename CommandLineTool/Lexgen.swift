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
    @Option(name: .customLong("atproto-configuration"))
    var configuration: String
    @Option(name: .long)
    var outdir: String?
    @Flag(name: .customLong("fetch-only"))
    var fetchOnly = false
  #endif

  mutating func run() async throws {
    #if os(macOS)
      let configurationURL = URL(filePath: configuration)
      let rootURL = configurationURL.deletingLastPathComponent()
      let config = try SourceControl.main(configurationURL: configurationURL, outdir: outdir)
      guard !fetchOnly else { return }
      try await SwiftAtprotoLex.main(
        outdir: rootURL.appending(component: config.module),
        path: SourceControl.lexiconsDirectoryURL(packageRootURL: rootURL).path(),
        generate: config.generate
      )
    #elseif os(Linux)
      print("swift-atproto lexgen is not supported on Linux yet.\n")
      print(Self.helpMessage())
    #endif
  }
}
