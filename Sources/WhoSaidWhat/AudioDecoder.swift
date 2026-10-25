import Foundation

enum AudioDecoder {
    /// The fallback executable is built without network protocols and shipped
    /// with the app. Never discover or execute a decoder from the user's PATH.
    static var executable: URL? {
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg"),
            URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
                .deletingLastPathComponent().appendingPathComponent("ffmpeg")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func decode(_ input: URL) async throws -> URL {
        guard let executable else {
            throw OptionsError("This recording needs the bundled audio decoder. Rebuild with ./build_app.sh to include it.")
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        let log = output.appendingPathExtension("log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errorOutput = try FileHandle(forWritingTo: log)
        defer { try? errorOutput.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", input.path,
            "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_f32le", "-f", "caf", output.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { finished in
                        if finished.terminationStatus == 0 { continuation.resume() }
                        else { continuation.resume(throwing: OptionsError("The bundled decoder could not read the recording's audio.")) }
                    }
                    do { try process.run() } catch { continuation.resume(throwing: error) }
                }
                try Task.checkCancellation()
            } onCancel: {
                if process.isRunning { process.terminate() }
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
