import Crypto
import Foundation

public var version: String { "0.35.2" }

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

public func lockFileURL(packageRootURL: URL) -> URL {
  packageRootURL.appending(component: ".atproto-lock.json")
}

public func main(configurationURL: URL, outdir: String?) throws -> LexiconConfig {
  let data = try Data(contentsOf: configurationURL)
  let originHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  let config = try JSONDecoder().decode(LexiconConfig.self, from: data, configuration: outdir)

  let rootURL = configurationURL.deletingLastPathComponent()
  let checkoutDirectory = checkoutDirectoryURL(packageRootURL: rootURL)
  let lexiconsDirectory = lexiconsDirectoryURL(packageRootURL: rootURL)
  let lockFileURL = lockFileURL(packageRootURL: rootURL)
  if let resolvedStore = try? LexiconsStore.load(from: lockFileURL),
    originHash == resolvedStore.originHash
  {
    return config
  }
  if FileManager.default.fileExists(atPath: lexiconsDirectory.path()) {
    try FileManager.default.removeItem(at: lexiconsDirectory)
  }
  try FileManager.default.createDirectory(at: lexiconsDirectory, withIntermediateDirectories: true)
  var resolvedDendencies = [ResolvedLexiconDependency]()
  for dependency in config.dependencies {
    var name = dependency.location.lastPathComponent
    if name.hasSuffix(".git") {
      name = String(name.dropLast(4))
    }
    let destURL = checkoutDirectory.appending(component: name)
    let clone: GitRepository
    if !GitRepositoryProvider.workingCopyExists(at: destURL.path()) {
      clone = try GitRepositoryProvider.createWorkingCopy(
        sourcePath: dependency.location.absoluteString,
        at: destURL.path())
    } else {
      clone = GitRepositoryProvider.openWorkingCopy(at: destURL.path())
      try clone.fetch()
    }

    let revision: String
    switch dependency.state {
    case .tag(let tag):
      try clone.checkout(tag: tag)
      revision = try clone.resolveRevision(tag: tag)
    case .revision(let identifier):
      revision = try clone.resolveRevision(identifier: identifier)
      try clone.checkout(revision: revision)
    }
    resolvedDendencies.append(.init(config: dependency, revision: revision))

    for lexicon in dependency.lexicons {
      if let nsIds = lexicon.nsIds {
        let srcBaseURL = destURL.appending(component: lexicon.rootPath)
        for nsId in nsIds {
          let dest = nsId.url(from: lexiconsDirectory)
          if !FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
          }
          try FileManager.default.copyItem(
            at: nsId.url(from: srcBaseURL),
            to: dest)
        }
      } else {
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
  }
  guard resolvedDendencies.count == config.dependencies.count else { return config }
  let store = LexiconsStore(originHash: originHash, generator: version, module: config.module, dependencies: resolvedDendencies)
  try store.write(to: lockFileURL)
  return config
}
