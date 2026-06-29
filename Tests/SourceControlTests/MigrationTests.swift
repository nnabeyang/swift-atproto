#if os(macOS) || os(Linux)

  import Foundation
  import Testing

  @testable import SourceControl

  struct MigrationTests {
    // Helpers ----------------------------------------------------------------

    /// Creates a temporary directory and registers it for removal at the end of the test.
    private static func makeTempDir() throws -> URL {
      let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("swift-atproto-migration-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }

    /// Creates a bare git repository at `bareURL` so the working-copy clone has something
    /// to point its `origin` at.
    @discardableResult
    private static func makeBareSource(at bareURL: URL) throws -> URL {
      try FileManager.default.createDirectory(at: bareURL, withIntermediateDirectories: true)
      _ = try GitShellHelper.run(["init", "--bare", "-q", bareURL.path])
      return bareURL
    }

    /// Creates a non-bare working copy at `cloneURL` whose origin points at `bareURL`.
    private static func makeWorkingCopy(at cloneURL: URL, from bareURL: URL) throws {
      try FileManager.default.createDirectory(at: cloneURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try GitRepositoryProvider.clone(origin: bareURL.path, destination: cloneURL.path, options: ["--no-checkout"])
    }

    private static func readOriginUrl(at workingCopy: URL) throws -> String {
      let repo = GitRepositoryProvider.openWorkingCopy(at: workingCopy.path)
      let raw = try repo.callGit(["config", "--get", "remote.origin.url"])
      return raw.trimmingCharacters(in: .newlines)
    }

    // Tests ------------------------------------------------------------------

    @Test func migratesLegacyWorkingCopyToNewLayout() throws {
      let root = try Self.makeTempDir()
      defer { try? FileManager.default.removeItem(at: root) }

      let bare = try Self.makeBareSource(at: root.appendingPathComponent("source.git", isDirectory: true))
      let legacy = root.appendingPathComponent("checkouts/repo", isDirectory: true)
      try Self.makeWorkingCopy(at: legacy, from: bare)

      let newURL = root.appendingPathComponent("checkouts/example.com/owner/repo", isDirectory: true)
      let remote = URL(string: "https://example.com/owner/repo.git")!
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)

      #expect(GitRepositoryProvider.workingCopyExists(at: newURL.path))
      #expect(!FileManager.default.fileExists(atPath: legacy.path))
      let originUrl = try Self.readOriginUrl(at: newURL)
      #expect(originUrl == "https://example.com/owner/repo.git")
    }

    @Test func skipsWhenNewLayoutAlreadyHasWorkingCopy() throws {
      let root = try Self.makeTempDir()
      defer { try? FileManager.default.removeItem(at: root) }

      let bareA = try Self.makeBareSource(at: root.appendingPathComponent("source-a.git", isDirectory: true))
      let bareB = try Self.makeBareSource(at: root.appendingPathComponent("source-b.git", isDirectory: true))

      let legacy = root.appendingPathComponent("checkouts/repo", isDirectory: true)
      try Self.makeWorkingCopy(at: legacy, from: bareA)

      let newURL = root.appendingPathComponent("checkouts/example.com/owner/repo", isDirectory: true)
      try Self.makeWorkingCopy(at: newURL, from: bareB)

      let remote = URL(string: "https://example.com/owner/repo.git")!
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)

      // Both directories must remain untouched.
      #expect(GitRepositoryProvider.workingCopyExists(at: newURL.path))
      #expect(GitRepositoryProvider.workingCopyExists(at: legacy.path))
    }

    @Test func skipsWhenLegacyIsNotAWorkingCopy() throws {
      let root = try Self.makeTempDir()
      defer { try? FileManager.default.removeItem(at: root) }

      let legacy = root.appendingPathComponent("checkouts/repo", isDirectory: true)
      try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
      try Data("hello".utf8).write(to: legacy.appendingPathComponent("file.txt"))

      let newURL = root.appendingPathComponent("checkouts/example.com/owner/repo", isDirectory: true)
      let remote = URL(string: "https://example.com/owner/repo.git")!
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)

      // Legacy untouched; nothing created at new path.
      #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("file.txt").path))
      #expect(!FileManager.default.fileExists(atPath: newURL.path))
    }

    @Test func refusesToOverwriteNonWorkingCopyAtNewPath() throws {
      let root = try Self.makeTempDir()
      defer { try? FileManager.default.removeItem(at: root) }

      let bare = try Self.makeBareSource(at: root.appendingPathComponent("source.git", isDirectory: true))
      let legacy = root.appendingPathComponent("checkouts/repo", isDirectory: true)
      try Self.makeWorkingCopy(at: legacy, from: bare)

      let newURL = root.appendingPathComponent("checkouts/example.com/owner/repo", isDirectory: true)
      try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
      try Data("junk".utf8).write(to: newURL.appendingPathComponent("placeholder"))

      let remote = URL(string: "https://example.com/owner/repo.git")!
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)

      // Legacy preserved; new path's junk preserved.
      #expect(GitRepositoryProvider.workingCopyExists(at: legacy.path))
      #expect(FileManager.default.fileExists(atPath: newURL.appendingPathComponent("placeholder").path))
    }

    @Test func idempotentReRunAfterSuccessfulMove() throws {
      let root = try Self.makeTempDir()
      defer { try? FileManager.default.removeItem(at: root) }

      let bare = try Self.makeBareSource(at: root.appendingPathComponent("source.git", isDirectory: true))
      let legacy = root.appendingPathComponent("checkouts/repo", isDirectory: true)
      try Self.makeWorkingCopy(at: legacy, from: bare)

      let newURL = root.appendingPathComponent("checkouts/example.com/owner/repo", isDirectory: true)
      let remote = URL(string: "https://example.com/owner/repo.git")!
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)
      // Second invocation with the legacy now missing must not throw.
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)
      #expect(GitRepositoryProvider.workingCopyExists(at: newURL.path))
    }

    @Test func setUrlUsesRedactedRemote() throws {
      let root = try Self.makeTempDir()
      defer { try? FileManager.default.removeItem(at: root) }

      let bare = try Self.makeBareSource(at: root.appendingPathComponent("source.git", isDirectory: true))
      let legacy = root.appendingPathComponent("checkouts/repo", isDirectory: true)
      try Self.makeWorkingCopy(at: legacy, from: bare)

      let newURL = root.appendingPathComponent("checkouts/example.com/owner/repo", isDirectory: true)
      let remote = URL(string: "https://oauth2:ghp_secret@example.com/owner/repo.git")!
      try migrateLegacyCheckout(legacyURL: legacy, newURL: newURL, remoteURL: remote)

      let originUrl = try Self.readOriginUrl(at: newURL)
      #expect(!originUrl.contains("ghp_secret"))
      #expect(!originUrl.contains("oauth2"))
      #expect(originUrl.contains("example.com/owner/repo.git"))
    }
  }

#endif
