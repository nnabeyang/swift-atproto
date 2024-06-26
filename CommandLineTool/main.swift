import ArgumentParser
import Foundation
import SourceControl
import SwiftAtprotoLex

struct Lexgen: ParsableCommand {
    private static let defaultModulePath = "Sources/Lexicon"
    static var configuration = CommandConfiguration(commandName: "swift-atproto", version: SwiftAtprotoLex.version)
    @Option(name: .customLong("atproto-configuration"))
    var configuration: String
    @Option(name: .long)
    var outdir: String?

    mutating func run() throws {
        let configurationtURL = URL(filePath: configuration)
        let data = try Data(contentsOf: configurationtURL)
        let config = try JSONDecoder().decode(LexiconConfig.self, from: data)
        try SourceControl.main(rootURL: configurationtURL.deletingLastPathComponent(), config: config)
        let outdir = outdir ?? config.module ?? Self.defaultModulePath
        try SwiftAtprotoLex.main(outdir: outdir, path: SourceControl.lexiconsDirectoryURL(packageRootURL: configurationtURL.deletingLastPathComponent()).path())
    }
}

Lexgen.main()
