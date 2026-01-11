import Foundation

public enum Git {
  static var tool: String { "git" }

  private nonisolated(unsafe) static var _gitEnvironment: [String: String]?
  private static let lock = NSLock()

  private static let underrideEnvironment = [
    "GIT_TERMINAL_PROMPT": "0",
    "GIT_SSH_COMMAND": "ssh -oBatchMode=yes",
  ]

  public static var environment: [String: String] {
    get {
      lock.lock()
      defer {
        lock.unlock()
      }
      var env = _gitEnvironment ?? ProcessInfo.processInfo.environment
      for (key, value) in underrideEnvironment {
        if env.keys.contains(key) { continue }
        env[key] = value
      }
      return env
    }
    set {
      lock.lock()
      defer {
        lock.unlock()
      }
      _gitEnvironment = newValue
    }
  }
}
