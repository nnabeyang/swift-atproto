import ATProtoCrypto
import Crypto
import Foundation
import SwiftAtproto

@testable import ATProtoSync

/// A commit as generated code exposes `com.atproto.space.defs#commit`.
struct SyncTestCommit: Codable, Hashable, PermissionedRepoCommitDescribing {
  var ver: Int
  var repo: FormatString<SwiftAtproto.DID>
  var space: FormatString<SpaceRef>
  var rev: FormatString<TID>
  var data: Data

  var permissionedRepoCommitVersion: Int { ver }
  var permissionedRepoCommitRepo: FormatString<SwiftAtproto.DID> { repo }
  var permissionedRepoCommitSpace: FormatString<SpaceRef> { space }
  var permissionedRepoCommitRevision: FormatString<TID> { rev }
  var permissionedRepoCommitData: Data { data }

  init(repository: RepoCommit, space: SpaceRef, repo: SwiftAtproto.DID, revision: TID) {
    ver = 1
    self.repo = .init(rawValue: repo.rawValue)
    self.space = .init(rawValue: space.rawValue)
    rev = .init(rawValue: revision.rawValue)
    data = repository.setHash.digest
  }
}

/// What a repo host returns for one request: the shared secret it derived and
/// the MAC it put in `Atproto-Space-Mac`.
struct SyncTestResponse {
  let authentication: RepoCommitAuthentication

  /// MACs `commit` with a fresh secret, as a repo host does for the request
  /// that asked for `space` and `repo`.
  init(
    commit: any PermissionedRepoCommitDescribing, space: SpaceRef, repo: SwiftAtproto.DID
  ) throws {
    let secret = SymmetricKey(size: .bits256)
    authentication = RepoCommitAuthentication(
      space: space, repo: repo, sharedSecret: secret,
      mac: try SpaceMAC.commitMAC(
        sharedSecret: secret,
        space: commit.permissionedRepoCommitSpace.rawValue,
        repo: commit.permissionedRepoCommitRepo.rawValue,
        rev: commit.permissionedRepoCommitRevision.rawValue,
        data: commit.permissionedRepoCommitData))
  }
}

extension RepoCommitAuthentication {
  func replacing(
    space: SpaceRef? = nil, repo: SwiftAtproto.DID? = nil, sharedSecret: SymmetricKey? = nil,
    mac: Data? = nil
  ) -> Self {
    Self(
      space: space ?? self.space, repo: repo ?? self.repo,
      sharedSecret: sharedSecret ?? self.sharedSecret, mac: mac ?? self.mac)
  }
}
