import Foundation
import SwiftAtproto

struct PermissionedRepoIndex: Sendable {
  let records: [RepoRecord]

  init(
    drisl data: Data,
    limits: RepoVerificationLimits
  ) throws {
    guard data.count <= limits.maximumIndexBytes else {
      throw RepoVerificationError.inputTooLarge(
        limit: limits.maximumIndexBytes, actual: data.count)
    }

    let index: [String: LexLink]
    do {
      index = try drislDecoder(
        maximumNestingDepth: limits.maximumNestingDepth,
        maximumContainerElements: limits.maximumIndexEntries,
        maximumStringBytes: 1024
      ).decode([String: LexLink].self, from: data)
    } catch {
      throw RepoVerificationError.malformedRepositoryIndex
    }

    records = try index.sorted { lhs, rhs in
      Self.canonicalKeyPrecedes(lhs.key, rhs.key)
    }.map { path, cid in
      try RepoRecord(path: path, cid: cid)
    }
  }

  private static func canonicalKeyPrecedes(_ lhs: String, _ rhs: String) -> Bool {
    let lhsBytes = Array(lhs.utf8)
    let rhsBytes = Array(rhs.utf8)
    if lhsBytes.count != rhsBytes.count {
      return lhsBytes.count < rhsBytes.count
    }
    return lhsBytes.lexicographicallyPrecedes(rhsBytes)
  }
}
