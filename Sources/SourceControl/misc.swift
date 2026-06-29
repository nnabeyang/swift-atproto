import Crypto
import Foundation

public var version: String { "0.40.0" }

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

// Where a lexicon dependency's files come from. Remote dependencies are
// cloned into `.lexicons/checkouts/`; local dependencies (`file://`) skip
// git entirely and are read directly from disk.
enum LexiconSource {
  case remote(checkoutURL: URL)
  case local(directoryURL: URL)
}

// Move a checkout from the legacy `<checkoutDir>/<repo>` location to the new
// `<checkoutDir>/<host>/<...path...>/<repo>` layout and rewrite its `origin`
// remote so future fetches honor the configured `remoteURL`. No-op when the
// new path already holds a valid working copy, when something else is occupying
// the new path, or when the legacy path is missing / isn't a real working copy.
func migrateLegacyCheckout(legacyURL: URL, newURL: URL, remoteURL: URL) throws {
  if GitRepositoryProvider.workingCopyExists(at: newURL.path()) { return }
  // If the new path is already occupied by something that isn't a working copy
  // (interrupted prior mv, manual stub, leftover state), don't overwrite it
  // here — the downstream `git clone` will surface a clear error instead of us
  // silently destroying user data.
  if FileManager.default.fileExists(atPath: newURL.path()) { return }
  guard GitRepositoryProvider.workingCopyExists(at: legacyURL.path()) else { return }
  try FileManager.default.createDirectory(
    at: newURL.deletingLastPathComponent(),
    withIntermediateDirectories: true)
  try FileManager.default.moveItem(at: legacyURL, to: newURL)
  let moved = GitRepositoryProvider.openWorkingCopy(at: newURL.path())
  _ = try moved.callGit(["remote", "set-url", "origin", remoteURL.absoluteString])
}

public func main(configurationURL: URL, outdir: String?) throws -> LexiconConfig {
  let data = try Data(contentsOf: configurationURL)
  let originHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  let config = try JSONDecoder().decode(LexiconConfig.self, from: data, configuration: outdir)

  let rootURL = configurationURL.deletingLastPathComponent()
  let checkoutDirectory = checkoutDirectoryURL(packageRootURL: rootURL)
  let lexiconsDirectory = lexiconsDirectoryURL(packageRootURL: rootURL)
  let lockFileURL = lockFileURL(packageRootURL: rootURL)

  // Resolve every dependency to its source (remote checkout or local path) and
  // run the legacy-layout migration up front, before the originHash fast-path.
  // Otherwise an unchanged configuration would let stale `<checkoutDir>/<repo>`
  // directories live on indefinitely after this upgrade.
  let preparedDependencies: [(LexiconDependency, LexiconSource)] = try config.dependencies.map {
    dependency in
    if dependency.location.scheme == "file" {
      return (dependency, .local(directoryURL: URL(fileURLWithPath: dependency.location.path)))
    }
    let location = try RepositoryLocation.parse(from: dependency.location)
    let destURL = checkoutDirectory.appending(path: location.segments.joined(separator: "/"))
    try migrateLegacyCheckout(
      legacyURL: checkoutDirectory.appending(component: location.segments.last!),
      newURL: destURL,
      remoteURL: dependency.location)
    return (dependency, .remote(checkoutURL: destURL))
  }

  let lexiconsIsExisting = FileManager.default.fileExists(atPath: lexiconsDirectory.path())
  if lexiconsIsExisting,
    let resolvedStore = try? LexiconsStore.load(from: lockFileURL),
    originHash == resolvedStore.originHash
  {
    return config
  }
  if lexiconsIsExisting {
    try FileManager.default.removeItem(at: lexiconsDirectory)
  }
  try FileManager.default.createDirectory(at: lexiconsDirectory, withIntermediateDirectories: true)
  var resolvedDendencies = [ResolvedLexiconDependency]()
  for (dependency, source) in preparedDependencies {
    let srcRootURL: URL
    let revision: String
    switch source {
    case .local(let directoryURL):
      // Local dependencies skip clone/fetch and ignore `dependency.state`; the
      // lockfile records a sentinel revision so the schema stays valid.
      srcRootURL = directoryURL
      revision = "local"
    case .remote(let destURL):
      let clone: GitRepository
      if !GitRepositoryProvider.workingCopyExists(at: destURL.path()) {
        try FileManager.default.createDirectory(
          at: destURL.deletingLastPathComponent(),
          withIntermediateDirectories: true)
        clone = try GitRepositoryProvider.createWorkingCopy(
          sourcePath: dependency.location.absoluteString,
          at: destURL.path())
      } else {
        clone = GitRepositoryProvider.openWorkingCopy(at: destURL.path())
        try clone.fetch()
      }
      switch dependency.state {
      case .tag(let tag):
        try clone.checkout(tag: tag)
        revision = try clone.resolveRevision(tag: tag)
      case .revision(let identifier):
        revision = try clone.resolveRevision(identifier: identifier)
        try clone.checkout(revision: revision)
      }
      srcRootURL = destURL
    }
    resolvedDendencies.append(.init(config: dependency, revision: revision))

    // For local dependencies install lexicons as symlinks so edits to the
    // source files are visible to the next codegen pass without re-running
    // fetch; for remote ones the checkout is the only stable copy so we copy.
    let install: (URL, URL) throws -> Void
    switch source {
    case .local:
      install = { src, dst in
        if FileManager.default.fileExists(atPath: dst.path()) { return }
        try FileManager.default.createSymbolicLink(at: dst, withDestinationURL: src)
      }
    case .remote:
      install = { src, dst in
        if FileManager.default.fileExists(atPath: dst.path()) { return }
        try FileManager.default.copyItem(at: src, to: dst)
      }
    }

    for lexicon in dependency.lexicons {
      if let nsIds = lexicon.nsIds {
        let srcBaseURL = srcRootURL.appending(component: lexicon.rootPath)
        for nsId in nsIds {
          let dest = nsId.url(from: lexiconsDirectory)
          if !FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
          }
          try install(nsId.url(from: srcBaseURL), dest)
        }
      } else {
        let srcBaseURL = srcRootURL.appending(component: lexicon.path)
        for name in try FileManager.default.contentsOfDirectory(atPath: srcBaseURL.path()) {
          let srcURL = srcBaseURL.appending(component: name)
          let lexiconBaseDirectory = lexiconsDirectory.appending(component: lexicon.prefix.replacingOccurrences(of: ".", with: "/"))
          if !FileManager.default.fileExists(atPath: lexiconBaseDirectory.path()) {
            try FileManager.default.createDirectory(at: lexiconBaseDirectory, withIntermediateDirectories: true)
          }
          let lexiconDirectory = lexiconBaseDirectory.appending(component: name)
          try install(srcURL, lexiconDirectory)
        }
      }
    }
  }
  guard resolvedDendencies.count == config.dependencies.count else { return config }
  let store = LexiconsStore(originHash: originHash, generator: version, module: config.module, dependencies: resolvedDendencies)
  try store.write(to: lockFileURL)
  return config
}
