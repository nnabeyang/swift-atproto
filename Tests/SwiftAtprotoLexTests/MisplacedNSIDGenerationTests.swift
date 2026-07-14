import Foundation
import XCTest

@testable import SwiftAtprotoLex

final class MisplacedNSIDGenerationTests: XCTestCase {
  private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("swift-atproto-misplaced-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeMinimalStrongRef(to fileURL: URL) throws {
    let json = """
      {
        "lexicon": 1,
        "id": "com.atproto.repo.strongRef",
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
      """
    try json.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  func testVendoredNSIDGeneratesUnderCanonicalNamespace() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appending(path: "input")
    let output = root.appending(path: "output")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let vendoredDir = input.appending(path: "jp/example/com/atproto/repo")
    try FileManager.default.createDirectory(at: vendoredDir, withIntermediateDirectories: true)
    try writeMinimalStrongRef(to: vendoredDir.appending(path: "strongRef.json"))

    try await SwiftAtprotoLex.main(outdir: output, path: input.path, generate: .client, pluginSource: .command)

    let clientURL = output.appending(path: "XRPCAPIClient.swift")
    let source = try String(contentsOf: clientURL, encoding: .utf8)

    XCTAssertFalse(source.contains("enum Jp "), "top-level `Jp` shadow enum must not be emitted")
    XCTAssertFalse(source.contains("Jp.Example"), "`Jp.Example` extension target must not appear")
    XCTAssertTrue(source.contains("public enum Com "), "canonical `Com` namespace must be emitted")
    XCTAssertTrue(source.contains("extension Com.Atproto "), "extension must attach to canonical `Com.Atproto`")
    XCTAssertTrue(source.contains("RepoStrongRef"), "canonical `RepoStrongRef` type must be emitted")
  }
}
