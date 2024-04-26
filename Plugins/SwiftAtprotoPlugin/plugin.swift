import Foundation
import PackagePlugin

@main
struct SwiftAtprotoPlugin {
    func codeGenerate(tool: PluginContext.Tool, arguments: [String]) throws {
        let codeGenerationExec = URL(fileURLWithPath: tool.path.string)
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
        try codeGenerate(tool: codeGenerationTool, arguments: arguments)
    }
}
