// Identifies the SwiftPM plugin context that drives codegen. Used to decide
// whether to emit placeholder files (required by build plugins because
// SwiftPM pre-declares outputs at plan time) or to skip writing altogether
// (when invoked manually via a command plugin).
//
// `@frozen` because callers may switch over the value without `@unknown
// default`, and we do not plan to add cases without bumping the major version.
@frozen public enum PluginSource: String, CaseIterable, Sendable {
  case build
  case command
}
