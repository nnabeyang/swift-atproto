#if os(macOS) || os(Linux)

  import Foundation
  import Testing

  @testable import SourceControl

  struct RepositoryLocationTests {
    @Test func httpsWithGitSuffix() throws {
      let url = URL(string: "https://example.com/owner/repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "owner", "repo"]))
    }

    @Test func httpsWithoutGitSuffix() throws {
      let url = URL(string: "https://example.com/owner/repo")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "owner", "repo"]))
    }

    @Test func httpsWithTrailingSlash() throws {
      let url = URL(string: "https://example.com/owner/repo/")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "owner", "repo"]))
    }

    @Test func preservesCase() throws {
      let url = URL(string: "https://example.com/Owner/Repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "Owner", "Repo"]))
    }

    @Test func singleSegmentPath() throws {
      let url = URL(string: "https://git.example.com/lex.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "git.example.com", "lex"]))
    }

    @Test func multiLevelSubgroup() throws {
      let url = URL(string: "https://example.com/group/sub/repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "group", "sub", "repo"]))
    }

    @Test func stripsOnlyLowercaseDotGit() throws {
      let url = URL(string: "https://example.com/owner/repo.GIT")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "owner", "repo.GIT"]))
    }

    @Test func stripsSingleDotGit() throws {
      let url = URL(string: "https://example.com/owner/repo.git.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "owner", "repo.git"]))
    }

    @Test func ownerEqualsRepoIsAllowed() throws {
      let url = URL(string: "https://example.com/foo/foo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "foo", "foo"]))
    }

    @Test func userinfoStrippedButPathParses() throws {
      let url = URL(string: "https://oauth2:ghp_secret@example.com/owner/repo.git")!
      let location = try RepositoryLocation.parse(from: url)
      #expect(location == RepositoryLocation(segments: ["https", "example.com", "owner", "repo"]))
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

    @Test func hostIsCaseFolded() throws {
      let lower = try RepositoryLocation.parse(from: URL(string: "https://example.com/owner/repo.git")!)
      let upper = try RepositoryLocation.parse(from: URL(string: "https://EXAMPLE.com/owner/repo.git")!)
      let mixed = try RepositoryLocation.parse(from: URL(string: "https://GitHub.com/owner/repo.git")!)
      #expect(lower == upper)
      #expect(mixed.segments == ["https", "github.com", "owner", "repo"])
    }

    @Test func differentSchemesAreDistinct() throws {
      let https = try RepositoryLocation.parse(from: URL(string: "https://example.com/owner/repo")!)
      let http = try RepositoryLocation.parse(from: URL(string: "http://example.com/owner/repo")!)
      let ssh = try RepositoryLocation.parse(from: URL(string: "ssh://git@example.com/owner/repo.git")!)
      #expect(https != http)
      #expect(https != ssh)
      #expect(http != ssh)
    }

    @Test func nonStandardPortDistinguishesCheckout() throws {
      let plain = try RepositoryLocation.parse(from: URL(string: "https://example.com/owner/repo.git")!)
      let custom = try RepositoryLocation.parse(from: URL(string: "https://example.com:8443/owner/repo.git")!)
      #expect(plain != custom)
    }

    @Test func defaultHttpsPortIsOmitted() throws {
      let plain = try RepositoryLocation.parse(from: URL(string: "https://example.com/owner/repo.git")!)
      let withDefault = try RepositoryLocation.parse(from: URL(string: "https://example.com:443/owner/repo.git")!)
      #expect(plain == withDefault)
    }

    @Test func defaultHttpPortIsOmitted() throws {
      let plain = try RepositoryLocation.parse(from: URL(string: "http://example.com/owner/repo.git")!)
      let withDefault = try RepositoryLocation.parse(from: URL(string: "http://example.com:80/owner/repo.git")!)
      #expect(plain == withDefault)
    }

    @Test func percentEncodedDotDotIsRejected() {
      let url = URL(string: "https://example.com/owner/%2e%2e/escape/repo")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }

    @Test func scpStyleUrlIsRejected() {
      // `git@example.com:owner/repo.git` parses with host=nil and is rejected.
      let url = URL(string: "git@example.com:owner/repo.git")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }

    @Test func bareGitOnlyRepoSegmentIsRejected() {
      let url = URL(string: "https://example.com/owner/.git")!
      #expect(throws: RepositoryLocationError.self) {
        _ = try RepositoryLocation.parse(from: url)
      }
    }
  }

#endif
