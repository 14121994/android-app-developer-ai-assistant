import Foundation
import PackagePlugin

@main
struct RunCoreLaunchTestsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let runner = try context.tool(named: "AndroidDevAgentCoreLaunchTests")
        let outputDirectory = context.pluginWorkDirectoryURL.appendingPathComponent("CoreLaunchTests", isDirectory: true)
        let outputFile = outputDirectory.appendingPathComponent("core-launch-tests.txt", isDirectory: false)

        return [
            .buildCommand(
                displayName: "Run AndroidDevAgentCore launch tests",
                executable: runner.url,
                arguments: [outputDirectory.path],
                outputFiles: [outputFile]
            )
        ]
    }
}
