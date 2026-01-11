import Foundation

public enum ProcessError: Error {
  case missingExecutableProgram(program: String)
}

public struct GitShellError: Error {
  let exitStatus: Int32
}

public enum GitShellHelper {
  @discardableResult
  public static func run(_ arguments: [String], environment: [String: String] = Git.environment) throws -> String {
    let program = Git.tool
    guard let executableURL = findExecutable(program) else {
      throw ProcessError.missingExecutableProgram(program: program)
    }
    let process = Process()
    process.environment = environment
    process.executableURL = executableURL
    process.arguments = arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    if process.terminationReason == .exit, process.terminationStatus == 0 {
      let data = stdout.fileHandleForReading.availableData
      return String(decoding: data, as: UTF8.self)
    } else {
      throw GitShellError(exitStatus: process.terminationStatus)
    }
  }

  static func findExecutable(_ program: String) -> URL? {
    let currentWorkingDirectory = URL(filePath: FileManager.default.currentDirectoryPath)
    let searchPaths = Git.environment["PATH"].flatMap { getEnvSearchPaths(pathString: $0) } ?? []
    return lookupExecutablePath(filename: program, currentWorkingDirectory: currentWorkingDirectory, searchPaths: searchPaths)
  }
}

public enum GitRepositoryProvider {
  public static func clone(
    origin: String,
    destination: String,
    options: [String]
  ) throws {
    let invocation: [String] =
      [
        "clone",
        "-c", "core.fsmonitor=false",
      ] + options + [origin, destination]
    try GitShellHelper.run(invocation)
  }

  public static func createWorkingCopy(sourcePath: String, at destinationPath: String) throws -> GitRepository {
    try clone(origin: sourcePath, destination: destinationPath, options: ["--no-checkout"])
    return openWorkingCopy(at: destinationPath)
  }

  public static func workingCopyExists(at path: String) -> Bool {
    guard FileManager.default.fileExists(atPath: path) else { return false }
    let repo = GitRepository(path: path)
    return (try? repo.checkoutExists()) ?? false
  }

  public static func openWorkingCopy(at path: String) -> GitRepository {
    GitRepository(path: path)
  }
}

public final class GitRepository {
  public let path: String
  private let lock = NSLock()
  private let isWorkingRepo: Bool
  init(path: String, isWorkingRepo: Bool = true) {
    self.path = path
    self.isWorkingRepo = isWorkingRepo
  }

  @discardableResult
  public func callGit(_ arguments: [String], environment: [String: String] = Git.environment) throws -> String {
    try GitShellHelper.run(["-C", path] + arguments, environment: environment)
  }

  public func checkout(tag: String) throws {
    _ = try lock.withLock {
      try callGit([
        "reset",
        "--hard",
        tag,
      ])
    }
  }

  public func checkout(revision: String) throws {
    try lock.withLock {
      _ = try callGit([
        "checkout",
        "-f",
        revision,
      ])
    }
  }

  func isBare() throws -> Bool {
    try lock.withLock {
      let output = try callGit([
        "rev-parse",
        "--is-bare-repository",
      ])
      return output == "true"
    }
  }

  func checkoutExists() throws -> Bool {
    try !isBare()
  }

  public func resolveRevision(tag: String) throws -> String {
    try resolveHash(specifier: "\(tag)^{commit}")
  }

  public func resolveRevision(identifier: String) throws -> String {
    try resolveHash(specifier: "\(identifier)^{commit}")
  }

  func resolveHash(specifier: String) throws -> String {
    try lock.withLock {
      let output = try callGit([
        "rev-parse",
        "--verify",
        specifier,
      ])
      return output.trimmingCharacters(in: .newlines)
    }
  }
}
