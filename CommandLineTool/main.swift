import ArgumentParser
import Foundation
import SwiftAtprotoLex

struct Lexgen: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "swift-atproto", version: "0.5.0")
    @Argument
    var path: String
    @Option(name: .long)
    var outdir: String

    mutating func run() throws {
        try SwiftAtprotoLex.main(outdir: outdir, path: path)
    }
}

Lexgen.main()
