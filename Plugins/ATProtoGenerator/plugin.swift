import Foundation
import PackagePlugin

@main struct ATProtoGeneratorPlugin {
  func createBuildCommands(
    pluginWorkDirectoryURL: URL,
    configurationFileURL: URL,
    tool: (String) throws -> PluginContext.Tool,
    sourceFiles: FileList,
    targetName: String
  ) throws -> [Command] {
    let tool = try tool("swift-atproto")
    let codeGenerationExec = tool.url
    var arguments = [String]()
    let outdir = pluginWorkDirectoryURL.appending(components: "GeneratedSources")
    arguments.append(contentsOf: ["--atproto-configuration", configurationFileURL.path()])
    arguments.append(contentsOf: ["--outdir", outdir.path()])
    return [
      .buildCommand(
        displayName: "Running swift-atproto-generator",
        executable: codeGenerationExec,
        arguments: arguments,
        environment: [:],
        inputFiles: [configurationFileURL],
        outputFiles: [
          outdir.appending(component: "UnknownATPValue.swift"),
          outdir.appending(component: "XRPCAPIProtocol.swift"),
          outdir.appending(component: "XRPCAPIClient.swift"),
        ]
      )
    ]
  }
}

extension ATProtoGeneratorPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    guard let swiftTarget = target as? SwiftSourceModuleTarget else {
      fatalError()
    }
    return try createBuildCommands(
      pluginWorkDirectoryURL: context.pluginWorkDirectoryURL,
      configurationFileURL: configurationFileURL(
        packageDirectoryURL: context.package.directoryURL,
        targetDirectoryURL: swiftTarget.directoryURL),
      tool: context.tool,
      sourceFiles: swiftTarget.sourceFiles,
      targetName: target.name
    )
  }

  private func configurationFileURL(packageDirectoryURL: URL, targetDirectoryURL: URL) -> URL {
    let targetURL = targetDirectoryURL.appending(component: ".atproto.json")
    if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
      return targetURL
    }
    return packageDirectoryURL.appending(component: ".atproto.json")
  }
}

#if canImport(XcodeProjectPlugin)
  import XcodeProjectPlugin

  extension ATProtoGeneratorPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
      try createBuildCommands(
        pluginWorkDirectoryURL: context.pluginWorkDirectoryURL,
        configurationFileURL: context.xcodeProject.directoryURL.appending(component: ".atproto.json"),
        tool: context.tool,
        sourceFiles: target.inputFiles,
        targetName: target.displayName
      )
    }
  }
#endif
