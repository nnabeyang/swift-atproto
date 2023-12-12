import ArgumentParser
import Foundation
import SwiftAtprotoLex

struct Lexgen: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "swift-atproto", version: "0.4.0")
    @Argument
    var path: String
    @Option(name: .long)
    var outdir: String
    @Option(name: .long)
    var prefix: String

    mutating func run() throws {
        try SwiftAtprotoLex.main(outdir: outdir, path: path, prefix: prefix)
    }
}

Lexgen.main()
