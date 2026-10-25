import Ear
import Foundation
import Voz
import Who

/// Build-time tool only. The shipped app never links or invokes this executable.
@main
struct BundleModels {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: BundleModels /path/to/Models")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let who = Who(directory: root.appendingPathComponent("Who").path)
        if !who.isDownloaded() {
            print("Fetching Who \(WhoModel.revision)…")
            _ = try await WhoModel.resolve(directory: root.appendingPathComponent("Who").path)
        }
        let vozPath = root.appendingPathComponent("Voz").path
        if !Voz.isDownloaded(directory: vozPath) {
            print("Fetching Voz \(VozModel.revision)…")
            try await Voz.download(directory: vozPath)
        }
        let ear = Ear(directory: root.appendingPathComponent("Ear").path)
        if !ear.isDownloaded() {
            print("Fetching Ear \(EarModel.revision)…")
            _ = try await EarModel.resolve(directory: root.appendingPathComponent("Ear").path)
        }
        let manifest = """
        Who: desert-ant-labs/who @ \(WhoModel.revision)
        Voz: desert-ant-labs/voz @ \(VozModel.revision)
        Ear: desert-ant-labs/ear @ \(EarModel.revision)
        Tongue: weights bundled with desert-ant-core 4.1.0
        Bundled SDK model downloads at runtime: disabled
        Apple system language downloads: allowed
        """
        try manifest.write(to: root.appendingPathComponent("MODELS.txt"), atomically: true, encoding: .utf8)
        print("Models ready at \(root.path)")
    }
}
