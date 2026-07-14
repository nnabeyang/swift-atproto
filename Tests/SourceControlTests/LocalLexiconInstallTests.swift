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

    private static func writeLexicon(at url: URL, id: String) throws {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(#"{"lexicon":1,"id":"\#(id)","defs":{}}"#.utf8).write(to: url)
    }

    // Tests ------------------------------------------------------------------

    @Test func localFileSchemeInstallsSymlinksPerFile() throws {
      // Without an nsIds allowlist the installer walks `<path>` recursively,
      // reads each JSON's `id`, and symlinks the individual file to its
      // canonical `<lexiconsDirectory>/<id-as-path>.json` location — file-level
      // rather than directory-level, so a new file added to the source tree
      // requires a re-run to appear (documented behavior change from the
      // pre-`prefix`-removal SourceControl).
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      let lexFile = source.appendingPathComponent("lexicons/com/example/feed/post.json")
      try Self.writeLexicon(at: lexFile, id: "com.example.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "path": "lexicons" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      let installed = project.appendingPathComponent(".lexicons/lexicons/com/example/feed/post.json")
      let attrs = try FileManager.default.attributesOfItem(atPath: installed.path)
      #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
      let target = try FileManager.default.destinationOfSymbolicLink(atPath: installed.path)
      #expect(target.hasSuffix("lexicons/com/example/feed/post.json"))
      #expect(FileManager.default.fileExists(atPath: installed.path))
    }

    @Test func destinationDerivedFromIdIgnoresSourceLayout() throws {
      // A lexicon can live at any path on disk and still install to its
      // canonical NSID location — this locks in the "install layout is derived
      // from the JSON `id`, not the file system" contract.
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      // Intentionally place the file under a mis-nested directory tree.
      let lexFile = source.appendingPathComponent("lexicons/wrong/place/for/canonical.json")
      try Self.writeLexicon(at: lexFile, id: "com.example.repo.strongRef")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "path": "lexicons" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      let installed = project.appendingPathComponent(".lexicons/lexicons/com/example/repo/strongRef.json")
      #expect(FileManager.default.fileExists(atPath: installed.path))
      // The mis-nested source path must NOT appear as a shadow entry.
      let shadow = project.appendingPathComponent(".lexicons/lexicons/wrong")
      #expect(!FileManager.default.fileExists(atPath: shadow.path))
    }

    @Test func nsIdsAllowlistInstallsListedFilesOnly() throws {
      // With `nsIds`, only the listed NSIDs are installed. Each JSON under
      // `<path>` is indexed by its declared `id`, so `path` can point at
      // either the lexicon root or an authority-scoped sub-directory — both
      // resolve to the same install destination.
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/post.json"), id: "com.example.feed.post")
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/like.json"), id: "com.example.feed.like")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{
              "path": "lexicons",
              "nsIds": ["com.example.feed.post"]
            }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      let installedPost = project.appendingPathComponent(".lexicons/lexicons/com/example/feed/post.json")
      let installedLike = project.appendingPathComponent(".lexicons/lexicons/com/example/feed/like.json")
      #expect(FileManager.default.fileExists(atPath: installedPost.path))
      #expect(!FileManager.default.fileExists(atPath: installedLike.path))
    }

    @Test func nsIdsAllowlistWorksWithAuthorityScopedPath() throws {
      // A `path` pointing at an authority-scoped sub-directory (as pre-existing
      // `.atproto.json` files often do) must resolve NSIDs by looking inside
      // that sub-directory, so `path: "lexicons/com/example"` combined with
      // `nsIds: ["com.example.feed.post"]` finds the file at
      // `<path>/feed/post.json` without doubling the authority segments.
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/post.json"), id: "com.example.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{
              "path": "lexicons/com/example",
              "nsIds": ["com.example.feed.post"]
            }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      let installed = project.appendingPathComponent(".lexicons/lexicons/com/example/feed/post.json")
      #expect(FileManager.default.fileExists(atPath: installed.path))
    }

    @Test func nsIdsAllowlistErrorsWhenEntryHasNoMatchingFile() throws {
      // A typo or missing lexicon in `nsIds` should surface a
      // `LexiconConfigError.missingNSID`, not the low-level "file couldn't be
      // opened" NSError the old path-join installer used to raise.
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/post.json"), id: "com.example.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{
              "path": "lexicons",
              "nsIds": ["com.example.feed.doesNotExist"]
            }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      #expect(throws: LexiconConfigError.missingNSID(nsId: "com.example.feed.doesNotExist", path: "lexicons")) {
        _ = try main(configurationURL: configURL, outdir: nil)
      }
    }

    @Test func legacyPrefixFieldIsAcceptedAndIgnored() throws {
      // `.atproto.json` from before the `prefix` removal must continue to
      // parse. The value is discarded; install destinations still come from
      // each JSON's `id`.
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/post.json"), id: "com.example.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "prefix": "com.example", "path": "lexicons" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      // Install continues to derive dest from the JSON `id` — the legacy
      // `prefix: "com.example"` field is silently ignored by the decoder.
      let installed = project.appendingPathComponent(".lexicons/lexicons/com/example/feed/post.json")
      #expect(FileManager.default.fileExists(atPath: installed.path))
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
            "lexicons": [{ "path": "../escape" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      #expect(throws: (any Error).self) {
        _ = try main(configurationURL: configURL, outdir: nil)
      }
      let installed = project.appendingPathComponent(".lexicons/lexicons/secret.json")
      #expect(!FileManager.default.fileExists(atPath: installed.path))
    }

    @Test func rejectsAbsoluteLexiconPath() throws {
      // Ensure an absolute `/etc` path can't slip through when URL append
      // silently strips the leading slash. `validatedLexiconSubpath` should
      // reject it up front.
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
            "lexicons": [{ "path": "/etc" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      #expect(throws: (any Error).self) {
        _ = try main(configurationURL: configURL, outdir: nil)
      }
      let leaked = project.appendingPathComponent(".lexicons/lexicons/secret.json")
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
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/post.json"), id: "com.example.feed.post")

      let configBody = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "path": "lexicons" }],
            "state": { "revision": "stale-sha" }
          }]
        }
        """
      let configURL = project.appendingPathComponent(".atproto.json")
      try configBody.write(to: configURL, atomically: true, encoding: .utf8)

      let configData = try Data(contentsOf: configURL)
      let originHash = SHA256.hash(data: configData).map { String(format: "%02x", $0) }.joined()
      let staleLockfile = """
        {
          "originHash": "\(originHash)",
          "generator": "0.0.0-stale",
          "module": "Sources/Out",
          "dependencies": [{
            "location": "file://\(source.path)",
            "lexicons": [{ "path": "lexicons" }],
            "state": { "revision": "stale-sha" }
          }]
        }
        """
      let lockfileURL = project.appendingPathComponent(".atproto-lock.json")
      try staleLockfile.write(to: lockfileURL, atomically: true, encoding: .utf8)
      try FileManager.default.createDirectory(
        at: project.appendingPathComponent(".lexicons/lexicons", isDirectory: true),
        withIntermediateDirectories: true)

      _ = try main(configurationURL: configURL, outdir: nil)

      let refreshed = try LexiconsStore.load(from: lockfileURL)
      let localDep = refreshed.dependencies.first { $0.location.scheme?.lowercased() == "file" }
      #expect(localDep?.state.revision == "local")
    }

    @Test func uppercaseFileSchemeIsTreatedAsLocal() throws {
      // Mirrors `localFileSchemeInstallsSymlinksPerFile` but with a `FILE://`
      // scheme to pin the case-insensitive contract between misc.swift and
      // RepositoryLocation.parse (which already lowercases).
      let root = try Self.makeTempRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let project = root.appendingPathComponent("proj", isDirectory: true)
      let source = root.appendingPathComponent("lex-src", isDirectory: true)
      try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
      try Self.writeLexicon(at: source.appendingPathComponent("lexicons/com/example/feed/post.json"), id: "com.example.feed.post")

      let configURL = project.appendingPathComponent(".atproto.json")
      let body = """
        {
          "generate": ["client"],
          "dependencies": [{
            "location": "FILE://\(source.path)",
            "lexicons": [{ "path": "lexicons" }],
            "state": { "tag": "local" }
          }]
        }
        """
      try body.write(to: configURL, atomically: true, encoding: .utf8)

      _ = try main(configurationURL: configURL, outdir: nil)

      let installed = project.appendingPathComponent(".lexicons/lexicons/com/example/feed/post.json")
      let attrs = try FileManager.default.attributesOfItem(atPath: installed.path)
      #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
    }
  }

#endif
