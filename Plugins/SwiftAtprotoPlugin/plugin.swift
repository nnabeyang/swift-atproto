import Foundation
import PackagePlugin

@main
struct SwiftAtprotoPlugin {
    func codeGenerate(tool: PluginContext.Tool, outputDirectoryPath: String?, configurationFilePath: String?) throws {
        let codeGenerationExec = tool.url
        var arguments = [String]()
        if let configurationFilePath = configurationFilePath {
            arguments.append(contentsOf: ["--atproto-configuration", configurationFilePath])
        }
        if let outputDirectoryPath = outputDirectoryPath {
            arguments.append(contentsOf: ["--outdir", outputDirectoryPath])
        }
        let process = try Process.run(codeGenerationExec, arguments: arguments)
        process.waitUntilExit()

        if process.terminationReason == .exit, process.terminationStatus == 0 {
            print("source code is generated.")
        } else {
            let problem = "\(process.terminationReason):\(process.terminationStatus)"
            Diagnostics.error("swift-atproto invocation failed: \(problem)")
        }
    }
}

extension SwiftAtprotoPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let codeGenerationTool = try context.tool(named: "swift-atproto")
        var argExtractor = ArgumentExtractor(arguments)
        let configurationFilePath: String?
        if argExtractor.extractOption(named: "atproto-configuration").first == nil {
            configurationFilePath = context.package.directoryURL.appending(component: ".atproto.json").path()
        } else {
            configurationFilePath = nil
        }
        let outputDirectoryPath = argExtractor.extractOption(named: "outdir").first
        try codeGenerate(tool: codeGenerationTool,
                         outputDirectoryPath: outputDirectoryPath,
                         configurationFilePath: configurationFilePath)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftAtprotoPlugin: XcodeCommandPlugin {
  func performCommand(context: XcodeProjectPlugin.XcodePluginContext, arguments: [String]) throws {
      let codeGenerationTool = try context.tool(named: "swift-atproto")
      var argExtractor = ArgumentExtractor(arguments)
      let configurationFilePath: String?
      if argExtractor.extractOption(named: "atproto-configuration").first == nil {
          configurationFilePath = context.xcodeProject.directoryURL.appending(component: ".atproto.json").path()
      } else {
          configurationFilePath = nil
      }

      let outputDirectoryPath = argExtractor.extractOption(named: "outdir").first
      try codeGenerate(tool: codeGenerationTool,
                       outputDirectoryPath: outputDirectoryPath,
                       configurationFilePath: configurationFilePath)
  }
}
#endif
