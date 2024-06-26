import ArgumentParser
import Foundation
import SourceControl
import SwiftAtprotoLex

struct Lexgen: ParsableCommand {
    private static let defaultModulePath = "Sources/Lexicon"
    static var configuration = CommandConfiguration(commandName: "swift-atproto", version: SourceControl.version)
    @Option(name: .customLong("atproto-configuration"))
    var configuration: String
    @Option(name: .long)
    var outdir: String?

    mutating func run() throws {
        let configurationtURL = URL(filePath: configuration)
        let data = try Data(contentsOf: configurationtURL)
        let config = try JSONDecoder().decode(LexiconConfig.self, from: data)
        let module = outdir ?? config.module ?? Self.defaultModulePath
        let rootURL = configurationtURL.deletingLastPathComponent()
        try SourceControl.main(rootURL: rootURL, config: config, module: module)
        try SwiftAtprotoLex.main(outdir: module, path: SourceControl.lexiconsDirectoryURL(packageRootURL: rootURL).path())
    }
}

Lexgen.main()
