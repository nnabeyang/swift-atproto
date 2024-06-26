import Foundation

public var version: String { "0.12.1" }

public func getEnvSearchPaths(pathString: String) -> [URL] {
    pathString.split(separator: ":").map { URL(filePath: String($0)) }
}

public func lookupExecutablePath(filename value: String?, currentWorkingDirectory: URL, searchPaths: [URL]) -> URL? {
    guard let value, !value.isEmpty else { return nil }
    var urls = [URL]()
    if value.hasPrefix("/") {
        urls.append(URL(filePath: value))
    } else if !value.contains("/") {
        urls.append(contentsOf: searchPaths.map { $0.appending(path: value) })
    } else {
        urls.append(currentWorkingDirectory.appending(path: value))
    }

    return urls.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
}

public func checkoutDirectoryURL(packageRootURL: URL) -> URL {
    packageRootURL.appending(components: ".lexicons", "checkouts")
}

public func lexiconsDirectoryURL(packageRootURL: URL) -> URL {
    packageRootURL.appending(components: ".lexicons", "lexicons")
}

public func main(rootURL: URL, config: LexiconConfig, module: String) throws {
    let checkoutDirectory = checkoutDirectoryURL(packageRootURL: rootURL)
    let lexiconsDirectory = lexiconsDirectoryURL(packageRootURL: rootURL)

    if !FileManager.default.fileExists(atPath: lexiconsDirectory.path()) {
        try FileManager.default.createDirectory(at: lexiconsDirectory, withIntermediateDirectories: true)
    }
    var resolvedDendencies = [ResolvedLexiconDependency]()
    for dependency in config.dependencies {
        var name = dependency.location.lastPathComponent
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        let destURL = checkoutDirectory.appending(component: name)
        if !GitRepositoryProvider.workingCopyExists(at: destURL.path()) {
            let clone = try GitRepositoryProvider.createWorkingCopy(sourcePath: dependency.location.absoluteString,
                                                                    at: destURL.path())
            let tag = dependency.state.tag
            try clone.checkout(tag: tag)
            let revision = try clone.resolveRevision(tag: tag)
            resolvedDendencies.append(.init(config: dependency, revision: revision))
        }
        for lexicon in dependency.lexicons {
            let srcBaseURL = destURL.appending(component: lexicon.path)
            for name in try FileManager.default.contentsOfDirectory(atPath: srcBaseURL.path()) {
                let srcURL = srcBaseURL.appending(component: name)
                let lexiconBaseDirectory = lexiconsDirectory.appending(component: lexicon.prefix.replacingOccurrences(of: ".", with: "/"))
                if !FileManager.default.fileExists(atPath: lexiconBaseDirectory.path()) {
                    try FileManager.default.createDirectory(at: lexiconBaseDirectory, withIntermediateDirectories: true)
                }
                let lexiconDirectory = lexiconBaseDirectory.appending(component: name)
                if !FileManager.default.fileExists(atPath: lexiconDirectory.path()) {
                    try FileManager.default.copyItem(at: srcURL, to: lexiconDirectory)
                }
            }
        }
    }
    if resolvedDendencies.count == config.dependencies.count {
        let store = LexiconsStore(generator: version, module: module, dependencies: resolvedDendencies)
        try store.write(to: rootURL.appending(component: ".atproto-lock.json"))
    }
}
