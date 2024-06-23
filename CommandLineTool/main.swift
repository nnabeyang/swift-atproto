import ArgumentParser
import Foundation
import SourceControl
import SwiftAtprotoLex

struct Lexgen: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "swift-atproto", version: SwiftAtprotoLex.version)
    @Option(name: .customLong("atproto-configuration"))
    var configuration: String
    @Option(name: .long)
    var outdir: String

    mutating func run() throws {
        let configurationtURL = URL(filePath: configuration)
        try SourceControl.main(configuration: configurationtURL)
        try SwiftAtprotoLex.main(outdir: outdir, path: SourceControl.lexiconsDirectoryURL(packageRootURL: configurationtURL.deletingLastPathComponent()).path())
    }
}

Lexgen.main()
