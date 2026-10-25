import Foundation
import Voz

enum TranscriptionBackend: String, CaseIterable, Identifiable, Sendable {
    case apple, voz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Speech"
        case .voz: "Voz · Desert Ant Labs"
        }
    }

    var detail: String {
        switch self {
        case .apple: "On-device macOS speech · downloads missing Apple language assets"
        case .voz: "25 European languages · Neural Engine · bundled model"
        }
    }
}

/// Models stay warm between files. Inference runs away from the UI actor.
actor LocalTranscribers {
    static let shared = LocalTranscribers()
    private var vozModel: Voz?

    func voz(_ url: URL, status: @escaping @Sendable (String?) -> Void,
             progress: @escaping @Sendable (Double) -> Void) async throws -> ([Word], Double) {
        if vozModel == nil {
            guard Voz.isDownloaded(directory: BundledModels.path("Voz")) else { throw BundledModels.missing("Voz") }
            status("Loading bundled Voz on the Neural Engine…")
            do { vozModel = try Voz(modelDirectory: BundledModels.directory("Voz")) }
            catch { throw OptionsError("Loading bundled Voz: \(error.localizedDescription) (\(String(reflecting: error)))") }
        }
        try Task.checkCancellation()
        guard let model = vozModel else { preconditionFailure("Voz failed to load") }
        status(nil)
        let result: Voz.Result
        do {
            result = try await model.transcribe(url) { update in
                progress(0.15 + update.fractionCompleted * 0.85)
            }
        } catch { throw OptionsError("Transcribing with Voz: \(error.localizedDescription) (\(String(reflecting: error)))") }
        try Task.checkCancellation()
        let words = Self.spacedWords(result.words.map { Word(text: $0.text, start: $0.start, end: $0.end) },
                                     duration: result.duration)
        progress(1)
        return (words, result.processingTime)
    }

    nonisolated static func validateVozLanguages(_ regions: [LanguageRegion]) throws {
        for code in Set(regions.compactMap(\.language)) where !Voz.supportedLanguages.contains(code) {
            throw PipelineError.unsupportedLanguage(code, TranscriptionBackend.voz.title)
        }
    }

    /// Voz returns bare words; the transcript/export representation keeps
    /// whitespace in each word. Preserve text order and bound times to the audio.
    static func spacedWords(_ words: [Word], duration: Double) -> [Word] {
        var previous = 0.0
        return words.compactMap { word in
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, word.start.isFinite, word.end.isFinite else { return nil }
            let start = min(duration, max(previous, word.start, 0))
            let end = min(duration, max(start, word.end))
            guard end > start else { return nil }
            previous = start
            return Word(text: " " + text, start: start, end: end)
        }
    }
}
