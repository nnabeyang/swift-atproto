import Crypto
import Foundation
import SwiftAtproto
import Testing

@testable import ATProtoCrypto
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

/// What a repo host returns for one request, and what the syncer verifies it
/// with: the encapsulation the MAC was requested with and the
/// `Atproto-Space-Commit`, `Signature-Input`, and `Signature` fields.
struct SyncTestResponse {
  let authentication: RepoCommitAuthentication

  /// Requests a MAC for `space` and `repo` with a fresh encapsulation, and
  /// answers it for `commit` as a repo host does.
  init(
    commit: any PermissionedRepoCommitDescribing, space: SpaceRef, repo: SwiftAtproto.DID
  ) throws {
    let author = try PrivateKey(type: .p256)
    let encapsulation = try SpaceKeyEncapsulation.encapsulate(authorKEMKey: author.publicKey.did)
    let request = try #require(
      try SpaceMAC.request(
        fromAcceptSignature: SpaceMAC.acceptSignature(profile: .commit, keyShare: encapsulation.keyShare),
        profile: .commit))
    let fields = try SpaceMAC.responseFields(
      commit: SpaceMACCommitField(
        ver: commit.permissionedRepoCommitVersion,
        repo: commit.permissionedRepoCommitRepo.rawValue,
        space: commit.permissionedRepoCommitSpace.rawValue,
        rev: commit.permissionedRepoCommitRevision.rawValue,
        data: commit.permissionedRepoCommitData),
      request: request,
      sharedSecret: try SpaceKeyEncapsulation.decapsulate(keyShare: request.keyShare, authorKEMKey: author))
    let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
    authentication = RepoCommitAuthentication(
      space: space, repo: repo, encapsulation: encapsulation,
      response: SpaceMACResponse(profile: .commit) { values[$0] })
  }
}

extension RepoCommitAuthentication {
  func replacing(
    space: SpaceRef? = nil, repo: SwiftAtproto.DID? = nil, sharedSecret: SymmetricKey? = nil,
    response: SpaceMACResponse? = nil
  ) -> Self {
    Self(
      space: space ?? self.space, repo: repo ?? self.repo,
      encapsulation: SpaceKeyEncapsulation(
        keyShare: encapsulation.keyShare, sharedSecret: sharedSecret ?? encapsulation.sharedSecret),
      response: response ?? self.response)
  }
}
