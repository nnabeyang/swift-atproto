import Crypto
import Foundation

public var version: String { "0.42.1" }

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

// Case-insensitive `file://` check, kept in sync with `RepositoryLocation.parse`
// which also lowercases the scheme before comparing. Used both by the dependency
// router and by the originHash fast-path so the two never disagree.
func isLocalDependency(_ location: URL) -> Bool {
  location.scheme?.lowercased() == "file"
}

public enum LexiconConfigError: Error, CustomStringConvertible, Equatable {
  case unsafeLexiconSubpath(field: String, value: String)
  case missingNSID(nsId: String, path: String)

  public var description: String {
    switch self {
    case .unsafeLexiconSubpath(let field, let value):
      return
        "Invalid lexicon \(field) \"\(value)\": must be a relative path with no `..`, `.`, or absolute prefix."
    case .missingNSID(let nsId, let path):
      return
        "NSID \"\(nsId)\" listed in `nsIds` was not found under `path: \"\(path)\"` — no lexicon JSON declares this `id`."
    }
  }
}

// Ensure the parent directory of `url` exists so a subsequent install call can
// write into it without hitting ENOENT. `FileManager` short-circuits when the
// directory is already present, so this is safe to call unconditionally.
func ensureParentDirectoryExists(for url: URL) throws {
  let parent = url.deletingLastPathComponent()
  if !FileManager.default.fileExists(atPath: parent.path(percentEncoded: false)) {
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
  }
}

// Recursively enumerate every `*.json` file under `baseURL`. Symlinks are not
// followed while walking (so a repo can't self-loop into `.git`), which
// mirrors the enclosing walkLexicons contract.
func collectLexiconJSONFiles(under baseURL: URL) throws -> [URL] {
  guard
    let enumerator = FileManager.default.enumerator(
      at: baseURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants])
  else {
    return []
  }
  var results: [URL] = []
  for case let fileURL as URL in enumerator {
    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
    if resourceValues.isRegularFile == true, fileURL.pathExtension == "json" {
      results.append(fileURL)
    }
  }
  // Sort so install ordering is deterministic across runs.
  return results.sorted { $0.path < $1.path }
}

// Extract the top-level `id` string from a lexicon JSON without materializing
// the full Codable graph — SourceControl doesn't own the lexicon schema, so we
// keep the read defensive and skip files where `id` is missing or not a string.
func readLexiconNSID(at url: URL) throws -> NSID? {
  let data = try Data(contentsOf: url)
  let object = try? JSONSerialization.jsonObject(with: data)
  guard let dict = object as? [String: Any], let id = dict["id"] as? String else {
    return nil
  }
  return NSID(rawValue: id)
}

// Reject `..`, `.`, and absolute paths in any lexicon-supplied sub-path so a
// malicious or typo-ed `.atproto.json` cannot escape `.lexicons/lexicons/` or
// the dependency's source root when joined via `appending(component:)`.
func validatedLexiconSubpath(_ raw: String, field: String) throws -> String {
  if raw.hasPrefix("/") {
    throw LexiconConfigError.unsafeLexiconSubpath(field: field, value: raw)
  }
  let segments = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  for segment in segments {
    if segment == "." || segment == ".." {
      throw LexiconConfigError.unsafeLexiconSubpath(field: field, value: raw)
    }
  }
  return segments.joined(separator: "/")
}

// Move a checkout from the legacy `<checkoutDir>/<repo>` location to the new
// `<checkoutDir>/<scheme>/<host>/<...path...>/<repo>` layout and rewrite its
// `origin` remote so future fetches honor the configured `remoteURL`. No-op
// when the new path already holds a valid working copy, when something else is
// occupying the new path, or when the legacy path is missing / isn't a real
// working copy.
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
  // Strip userinfo / query / fragment before writing the URL into `.git/config`
  // so a `https://oauth2:ghp_xxx@…` location from `.atproto.json` never lands
  // on disk in plaintext. The credential helper can still attach auth at fetch
  // time via the redacted host.
  _ = try moved.callGit(["remote", "set-url", "origin", redactedRemoteOrigin(from: remoteURL)])
}

func redactedRemoteOrigin(from url: URL) -> String {
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return url.absoluteString
  }
  components.user = nil
  components.password = nil
  components.query = nil
  components.fragment = nil
  return components.string ?? url.absoluteString
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
    if isLocalDependency(dependency.location) {
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

  // Local dependencies are mutable — the user can edit the source tree
  // between runs and a previous swift-atproto release may have written a
  // lockfile that still treats them as remote. Skip the originHash fast-path
  // whenever any dep is local so the install loop always re-runs and
  // rewrites `revision = "local"`.
  let hasLocalDependency = preparedDependencies.contains { _, source in
    if case .local = source { return true }
    return false
  }
  let lexiconsIsExisting = FileManager.default.fileExists(atPath: lexiconsDirectory.path())
  if !hasLocalDependency,
    lexiconsIsExisting,
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
      let safePath = try validatedLexiconSubpath(lexicon.path, field: "path")
      let srcBaseURL = srcRootURL.appending(component: safePath)
      // Walk `<path>` once and index every JSON by the NSID it declares. This
      // lets both the allowlist (`nsIds`) and enumerate-everything modes look
      // up sources by id — which in turn lets `path` point at either the
      // lexicon root or an authority-scoped sub-directory without any config
      // migration on the caller's side.
      var idIndex: [String: URL] = [:]
      for srcURL in try collectLexiconJSONFiles(under: srcBaseURL) {
        guard let nsId = try readLexiconNSID(at: srcURL) else {
          FileHandle.standardError.write(
            Data(
              "warning: skipping \(srcURL.path()): JSON does not carry a top-level `id` string.\n"
                .utf8))
          continue
        }
        idIndex[nsId.rawValue] = srcURL
      }
      let selected: [(NSID, URL)]
      if let nsIds = lexicon.nsIds {
        selected = try nsIds.map { nsId in
          guard let srcURL = idIndex[nsId.rawValue] else {
            throw LexiconConfigError.missingNSID(nsId: nsId.rawValue, path: lexicon.path)
          }
          return (nsId, srcURL)
        }
      } else {
        selected = idIndex.keys.sorted().map { id in (NSID(rawValue: id), idIndex[id]!) }
      }
      for (nsId, srcURL) in selected {
        let dest = nsId.url(from: lexiconsDirectory)
        try ensureParentDirectoryExists(for: dest)
        try install(srcURL, dest)
      }
    }
  }
  guard resolvedDendencies.count == config.dependencies.count else { return config }
  let store = LexiconsStore(originHash: originHash, generator: version, module: config.module, dependencies: resolvedDendencies)
  try store.write(to: lockFileURL)
  return config
}
