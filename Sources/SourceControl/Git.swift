import Foundation

public enum Git {
    static var tool: String { "git" }

    private static var _gitEnvironment = ProcessInfo.processInfo.environment

    private static let underrideEnvironment = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": "ssh -oBatchMode=yes",
    ]

    public static var environment: [String: String] {
        get {
            var env = _gitEnvironment
            for (key, value) in underrideEnvironment {
                if env.keys.contains(key) { continue }
                env[key] = value
            }
            return env
        }
        set {
            _gitEnvironment = newValue
        }
    }
}
