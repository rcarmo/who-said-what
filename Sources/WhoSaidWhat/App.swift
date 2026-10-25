import AVFoundation
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct WhoSaidWhatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // `WhoSaidWhat --print file.wav [--format txt|srt|vtt|json] [--names "A,B"]` runs without the window and prints the transcript.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--install-apple-assets") {
            Task {
                do {
                    guard index + 1 < args.count else { throw OptionsError("--install-apple-assets requires base language codes, for example en,es,it.") }
                    let languages = args[index + 1].split(separator: ",").map(String.init)
                    try await AppleSpeech.install(languages: languages)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("Apple Speech setup: \(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            return
        }
        if args.contains("--help") {
            print(CommandLineOptions.usage)
            exit(0)
        }
        if args.contains("--print") {
            Task {
                var operation = "Reading command-line options"
                do {
                    let options = try CommandLineOptions(args)
                    let url = options.input
                    operation = "Opening audio"
                    let prepared = try await Pipeline.prepareAudio(for: url)
                    let audio = prepared.url
                    defer { if audio != url { try? FileManager.default.removeItem(at: audio) } }
                    operation = "Reading audio duration"
                    let duration = try await AVURLAsset(url: audio).load(.duration).seconds
                    guard duration.isFinite, duration > 0 else { throw PipelineError.emptyAudio }
                    FileHandle.standardError.write(Data(String(format: "Audio decoded: %.3fs\n", duration).utf8))
                    for warning in prepared.warnings { FileHandle.standardError.write(Data("warning: \(warning)\n".utf8)) }
                    operation = "Running diarization and transcription"
                    let progress = HeadlessProgress()
                    async let d = Pipeline.diarize(audio) { _ in }
                    async let w = Pipeline.transcribe(audio, duration: duration, backend: options.backend, language: options.language,
                        status: { if let note = $0 { progress.report(note) } },
                        progress: { progress.report(String(format: "Transcribing · %.0f%%", $0 * 100)) })
                    let ((diarization, whoTime), transcription) = try await (d, w)
                    let words = transcription.words
                    let speechTime = transcription.seconds
                    guard !words.isEmpty else { throw PipelineError.noSpeech }
                    // Stats go to stderr so `--print file > transcript.srt` writes a clean file.
                    let stats = String(format: "%d speakers, %d words · Who: %.2fs (%.0fx realtime) · speech to text: %.2fs (%.0fx realtime)\n",
                                       diarization.speakerCount, words.count,
                                       whoTime, duration / whoTime, speechTime, duration / speechTime)
                    FileHandle.standardError.write(Data(stats.utf8))
                    FileHandle.standardError.write(Data("\(options.backend.title) · \(transcription.languageSummary)\n".utf8))
                    for warning in transcription.warnings {
                        FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
                    }
                    let aligned = Pipeline.align(words: words, turns: diarization.turns)
                    // Name speakers in order of first transcribed appearance, as in the UI.
                    let segments = Pipeline.renumber(aligned)
                    let rendered = Transcript(fileName: url.lastPathComponent, duration: duration,
                        segments: segments, names: options.names, languages: transcription.languages, warnings: prepared.warnings).render(options.format)
                    if let output = options.output {
                        try rendered.write(to: output, atomically: true, encoding: .utf8)
                        FileHandle.standardError.write(Data("Saved \(output.path)\n".utf8))
                    } else { print(rendered, terminator: "") }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("error: \(operation): \(error.localizedDescription) (\(String(reflecting: error)))\n".utf8))
                    exit(1)
                }
            }
            return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Who Said What") {
            ContentView()
                .frame(minWidth: 820, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 720)
        // Always open a fresh window, never a restored "closed" state.
        .restorationBehavior(.disabled)
    }
}

/// Progress belongs on stderr, leaving piped subtitles/transcripts clean.
final class HeadlessProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    func report(_ note: String) {
        lock.lock()
        defer { lock.unlock() }
        let assetUpdate = note.hasPrefix("Downloading Apple Speech") || note.hasPrefix("Preparing Apple Speech assets")
        guard assetUpdate || Date().timeIntervalSince(last) >= 30 else { return }
        last = Date()
        FileHandle.standardError.write(Data("\(note)\n".utf8))
    }
}
