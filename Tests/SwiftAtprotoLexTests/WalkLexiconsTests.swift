import Foundation
import XCTest

@testable import SwiftAtprotoLex

final class WalkLexiconsTests: XCTestCase {
  private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("swift-atproto-walk-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func testCollectsJSONFilesThroughDirectorySymlinks() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source", isDirectory: true)
    let nested = source.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: nested.appendingPathComponent("a.json"))

    let base = root.appendingPathComponent("base", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let link = base.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)

    let urls = collectJSONFileURLs(at: base)
    let names = urls.map { $0.lastPathComponent }.sorted()
    XCTAssertEqual(names, ["a.json"])
  }

  func testTerminatesOnSymlinkLoop() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let base = root.appendingPathComponent("base", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: base.appendingPathComponent("ok.json"))
    let loop = base.appendingPathComponent("loop", isDirectory: true)
    // `loop` points back to its own parent — without cycle detection the
    // recursive walker would re-enter forever.
    try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: base)

    let urls = collectJSONFileURLs(at: base)
    // The single real JSON is reported exactly once even though the cycle
    // exposes it through `base/loop/ok.json`, `base/loop/loop/ok.json`, ...
    XCTAssertEqual(urls.map(\.lastPathComponent), ["ok.json"])
  }
}
