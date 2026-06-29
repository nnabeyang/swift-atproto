#if os(macOS) || os(Linux)

  import Crypto
  import Foundation
  import Testing

  @testable import SourceControl

  struct LocalLexiconInstallTests {
    // Helpers ----------------------------------------------------------------

    private static func makeTempRoot() throws -> URL {
      let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("swift-atproto-local-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }

    /// Sets up a fake project skeleton with `.atproto.json` containing `body` and an
    /// empty source tree at `lex-src/`. Returns the configuration URL and the source root.
    private static func makeProject(_ body: String) throws -> (config: URL, source: URL) {
      let root = try makeTempRoot()
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
      let configURL = project.appendingPathComponent(".atproto.json")
      try body.write(to: configURL, atomically: true, encoding: .utf8)
      return (configURL, source)
    }

    private static func writeLexicon(at url: URL, id: String) throws {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(#"{"lexicon":1,"id":"\#(id)","defs":{}}"#.utf8).write(to: url)
    }

    // Tests ------------------------------------------------------------------

    @Test func localFileSchemeInstallsSymlinks() throws {
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      let lexFile = source.appendingPathComponent("lexicons/app/bsky/feed/post.json")
      try Self.writeLexicon(at: lexFile, id: "app.bsky.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "prefix": "app.bsky", "path": "lexicons/app/bsky" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      // For non-nsIds the installer symlinks each top-level entry of
      // `lexicon.path`. With `path: "lexicons/app/bsky"` the only entry is `feed`,
      // so a directory symlink lives at `.lexicons/lexicons/app/bsky/feed`.
      let installedDir = project.appendingPathComponent(".lexicons/lexicons/app/bsky/feed")
      let attrs = try FileManager.default.attributesOfItem(atPath: installedDir.path)
      #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
      let target = try FileManager.default.destinationOfSymbolicLink(atPath: installedDir.path)
      #expect(target.hasSuffix("lexicons/app/bsky/feed"))
      // The file is reachable through the symlink.
      #expect(FileManager.default.fileExists(atPath: installedDir.appendingPathComponent("post.json").path))
    }

    @Test func rejectsLexiconPathWithParentTraversal() throws {
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      let escape = root.appendingPathComponent("escape", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
      try Self.writeLexicon(at: escape.appendingPathComponent("secret.json"), id: "secret")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "prefix": "evil", "path": "../escape" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      #expect(throws: (any Error).self) {
        _ = try main(configurationURL: configURL, outdir: nil)
      }
      // The escape file must never appear under .lexicons/lexicons/.
      let installed = project.appendingPathComponent(".lexicons/lexicons/evil/secret.json")
      #expect(!FileManager.default.fileExists(atPath: installed.path))
    }

    @Test func rejectsRootPathWithParentTraversal() throws {
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      let escape = root.appendingPathComponent("escape", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
      // nsIds path joins as `<rootPath>/<nsid_components>.json`. So if rootPath
      // is `../escape` and we point nsId at `secret`, the source URL becomes
      // `<source>/../escape/secret.json`.
      try Self.writeLexicon(at: escape.appendingPathComponent("secret.json"), id: "secret")

      let configURL = project.appendingPathComponent(".atproto.json")
      // `path: "../escape/evil"` makes rootPath="../escape" (strips the prefix-as-path).
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{
              "prefix": "evil",
              "path": "../escape/evil",
              "nsIds": ["secret"]
            }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      #expect(throws: (any Error).self) {
        _ = try main(configurationURL: configURL, outdir: nil)
      }
    }

    @Test func rejectsAbsoluteLexiconPath() throws {
      // Create a sibling `etc` directory inside the source root so that an
      // absolute `/etc` path would, if URL append silently stripped the leading
      // slash, point at real content. We assert the install rejects the path
      // explicitly rather than relying on the missing-directory side effect.
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("etc/secret.json"), id: "secret")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "prefix": "evil", "path": "/etc" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      #expect(throws: (any Error).self) {
        _ = try main(configurationURL: configURL, outdir: nil)
      }
      // The secret must never leak into the project's lexicons directory.
      let leaked = project.appendingPathComponent(".lexicons/lexicons/evil/secret.json")
      #expect(!FileManager.default.fileExists(atPath: leaked.path))
    }

    @Test func staleLockfileIsRefreshedForLocalDependency() throws {
      // Simulates the upgrade path where an older swift-atproto wrote a lockfile
      // with `revision = <user-supplied-sha>` for a file:// dep (because file://
      // was treated as remote), then the user upgrades to the version with
      // file:// → .local routing. The originHash matches the current config so
      // the fast-path would normally return early and leave the stale revision
      // in place; with the bypass, `main()` must re-run install and rewrite the
      // revision to "local".
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/app/bsky/feed/post.json"), id: "app.bsky.feed.post")

      let configBody = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "prefix": "app.bsky", "path": "lexicons/app/bsky" }],
            "state": { "revision": "stale-sha" }
          }]
        }
        """
      let configURL = project.appendingPathComponent(".atproto.json")
      try configBody.write(to: configURL, atomically: true, encoding: .utf8)

      // Pre-seed the lockfile with the *same* originHash as the config above
      // and a revision that lies (`"stale-sha"` instead of `"local"`).
      let configData = try Data(contentsOf: configURL)
      let originHash = SHA256.hash(data: configData).map { String(format: "%02x", $0) }.joined()
      let staleLockfile = """
        {
          "originHash": "\(originHash)",
          "generator": "0.0.0-stale",
          "module": "Sources/Out",
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "prefix": "app.bsky", "path": "lexicons/app/bsky" }],
            "state": { "revision": "stale-sha" }
          }]
        }
        """
      let lockfileURL = project.appendingPathComponent(".atproto-lock.json")
      try staleLockfile.write(to: lockfileURL, atomically: true, encoding: .utf8)
      // The fast-path also requires `.lexicons/lexicons/` to exist on disk.
      try FileManager.default.createDirectory(
        at: project.appendingPathComponent(".lexicons/lexicons", isDirectory: true),
        withIntermediateDirectories: true)

      _ = try main(configurationURL: configURL, outdir: nil)

      let refreshed = try LexiconsStore.load(from: lockfileURL)
      let localDep = refreshed.dependencies.first { $0.location.scheme?.lowercased() == "file" }
      #expect(localDep?.state.revision == "local")
    }

    @Test func uppercaseFileSchemeIsTreatedAsLocal() throws {
      // Mirrors `localFileSchemeInstallsSymlinks` but with a `FILE://` scheme to
      // pin the case-insensitive contract between misc.swift and
      // RepositoryLocation.parse (which already lowercases).
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/app/bsky/feed/post.json"), id: "app.bsky.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "FILE://\(source.path)",
            "lexicons": [{ "prefix": "app.bsky", "path": "lexicons/app/bsky" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      let installedDir = project.appendingPathComponent(".lexicons/lexicons/app/bsky/feed")
      let attrs = try FileManager.default.attributesOfItem(atPath: installedDir.path)
      #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
    }
  }

#endif
