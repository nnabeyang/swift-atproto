import Foundation
import XCTest

@testable import SwiftAtprotoLex

final class DuplicateNSIDTests: XCTestCase {
  private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("swift-atproto-dup-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func minimalStrongRef(id: String) -> Data {
    """
    {
      "lexicon": 1,
      "id": "\(id)",
      "description": "A URI with a content-hash fingerprint.",
      "defs": {
        "main": {
          "type": "object",
          "required": ["uri", "cid"],
          "properties": {
            "uri": {"type": "string", "format": "at-uri"},
            "cid": {"type": "string", "format": "cid"}
          }
        }
      }
    }
    """.data(using: .utf8)!
  }

  func testDuplicateNSIDFailsFast() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let canonicalDir = root.appending(path: "com/atproto/repo")
    try FileManager.default.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
    let canonical = canonicalDir.appending(path: "strongRef.json")
    try minimalStrongRef(id: "com.atproto.repo.strongRef").write(to: canonical)

    let vendoredDir = root.appending(path: "sh/tangled/com/atproto/repo")
    try FileManager.default.createDirectory(at: vendoredDir, withIntermediateDirectories: true)
    let vendored = vendoredDir.appending(path: "strongRef.json")
    try minimalStrongRef(id: "com.atproto.repo.strongRef").write(to: vendored)

    let fileURLs = collectJSONFileURLs(at: root)
    do {
      _ = try await decodeSchemasByPrefix(from: fileURLs)
      XCTFail("expected SchemaDecodeError.duplicateNSID")
    } catch let SchemaDecodeError.duplicateNSID(id, firstPath, secondPath) {
      XCTAssertEqual(id, "com.atproto.repo.strongRef")
      // `sortedEntries` orders by URL path, so the canonical layout (which
      // sorts lexicographically before the vendored one) is reported first.
      XCTAssertTrue(firstPath.path.contains("/com/atproto/repo/"))
      XCTAssertFalse(firstPath.path.contains("/sh/tangled/"))
      XCTAssertTrue(secondPath.path.contains("/sh/tangled/com/atproto/repo/"))
    }
  }
}
