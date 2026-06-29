#if os(macOS) || os(Linux)

  import Foundation
  import Testing

  @testable import SourceControl

  struct RepositoryLocationTests {
    @Test func httpsWithGitSuffix() throws {
      let url = URL(string: "https://example.com/owner/repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "owner", "repo"]))
    }

    @Test func httpsWithoutGitSuffix() throws {
      let url = URL(string: "https://example.com/owner/repo")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "owner", "repo"]))
    }

    @Test func httpsWithTrailingSlash() throws {
      let url = URL(string: "https://example.com/owner/repo/")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "owner", "repo"]))
    }

    @Test func preservesCase() throws {
      let url = URL(string: "https://example.com/Owner/Repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "Owner", "Repo"]))
    }

    @Test func singleSegmentPath() throws {
      let url = URL(string: "https://git.example.com/lex.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["git.example.com", "lex"]))
    }

    @Test func multiLevelSubgroup() throws {
      let url = URL(string: "https://example.com/group/sub/repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "group", "sub", "repo"]))
    }

    @Test func stripsOnlyLowercaseDotGit() throws {
      let url = URL(string: "https://example.com/owner/repo.GIT")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "owner", "repo.GIT"]))
    }

    @Test func stripsSingleDotGit() throws {
      let url = URL(string: "https://example.com/owner/repo.git.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "owner", "repo.git"]))
    }

    @Test func ownerEqualsRepoIsAllowed() throws {
      let url = URL(string: "https://example.com/foo/foo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "foo", "foo"]))
    }

    @Test func userinfoStrippedButPathParses() throws {
      let url = URL(string: "https://oauth2:ghp_secret@example.com/owner/repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["example.com", "owner", "repo"]))
    }

    @Test func throwsWhenPathIsEmpty() {
      let url = URL(string: "https://example.com/")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }

    @Test func throwsForFileURL() {
      let url = URL(string: "file:///tmp/repo")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }

    @Test func throwsOnDotDotSegment() {
      let url = URL(string: "https://example.com/owner/../escape/repo")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }

    @Test func throwsOnDotSegment() {
      let url = URL(string: "https://example.com/owner/./repo")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }

    @Test func errorRedactsUserinfo() {
      let url = URL(string: "https://oauth2:ghp_secret@example.com/")!
      do {
        _ = try RepositoryLocation.parse(from: url)
        Issue.record("expected throw")
      } catch let error as RepositoryLocationError {
        let message = error.description
        #expect(!message.contains("ghp_secret"))
        #expect(!message.contains("oauth2"))
      } catch {
        Issue.record("unexpected error type: \(type(of: error))")
      }
    }
  }

#endif
