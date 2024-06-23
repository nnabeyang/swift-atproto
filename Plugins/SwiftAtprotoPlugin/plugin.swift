import Foundation
import PackagePlugin

@main
struct SwiftAtprotoPlugin {
    func codeGenerate(tool: PluginContext.Tool, arguments: [String], configurationFilePath: String?) throws {
        let codeGenerationExec = URL(fileURLWithPath: tool.path.string)
        var arguments = arguments
        if let configurationFilePath = configurationFilePath {
            arguments.append(contentsOf: ["--atproto-configuration", configurationFilePath])
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
            configurationFilePath = URL(filePath: context.package.directory.string).appending(component: ".atproto.json").path()
        } else {
            configurationFilePath = nil
        }
        try codeGenerate(tool: codeGenerationTool, arguments: arguments, configurationFilePath: configurationFilePath)
    }
}
