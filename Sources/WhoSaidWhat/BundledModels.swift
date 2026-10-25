import Foundation

enum BundledModels {
    /// App resources in a packaged build; a Models sibling for SwiftPM/CLI runs.
    static var root: URL {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let candidates = [resources.appendingPathComponent("Models"),
            URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
                .deletingLastPathComponent().appendingPathComponent("Models")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    static func directory(_ model: String) -> URL { root.appendingPathComponent(model, isDirectory: true) }
    static func path(_ model: String) -> String { directory(model).path }

    static func missing(_ model: String) -> OptionsError {
        OptionsError("The bundled \(model) model is missing or incomplete. Rebuild with ./build_app.sh to package the models. No model downloads are performed by the app.")
    }
}
