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
  #if os(macOS) || os(Linux)
    @Option(name: .customLong("atproto-configuration"))
    var configuration: String
    @Option(name: .long)
    var outdir: String?
    @Flag(name: .customLong("fetch-only"))
    var fetchOnly = false
  #endif

  mutating func run() async throws {
    #if os(macOS) || os(Linux)
      let configurationURL = URL(filePath: configuration)
      let rootURL = configurationURL.deletingLastPathComponent()
      let config = try SourceControl.main(configurationURL: configurationURL, outdir: outdir)
      guard !fetchOnly else { return }
      let outdirURL = outdir.map { URL(filePath: $0) } ?? rootURL.appending(component: config.module)
      try await SwiftAtprotoLex.main(
        outdir: outdirURL,
        path: SourceControl.lexiconsDirectoryURL(packageRootURL: rootURL).path(),
        generate: config.generate
      )
    #endif
  }
}
