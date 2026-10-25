import AVFoundation
import Ear
import Foundation
import Tongue

struct LanguageRegion: Codable, Equatable, Sendable {
    var start: Double
    var end: Double
    let language: String?
    let confidence: Double
    var source: String = "audio"
}

struct TranscriptionOutput: Sendable {
    let words: [Word]
    let seconds: Double
    let languages: [LanguageRegion]
    let warnings: [String]

    var languageSummary: String {
        let codes = Set(languages.compactMap(\.language)).sorted()
        return codes.isEmpty ? "Language uncertain" : codes.map(LanguageDetection.name).joined(separator: ", ")
    }
}

enum PipelineError: LocalizedError {
    case emptyAudio, noSpeech
    case uncertainLanguage(Double)
    case unsupportedLanguage(String, String)

    var errorDescription: String? {
        switch self {
        case .emptyAudio: "The file contains no readable audio."
        case .noSpeech: "No speech was recognized. Try another transcription model or set the language manually."
        case .uncertainLanguage(let time):
            "The spoken language near \(Transcript.clock(time)) is uncertain. Choose Voz for multilingual decoding, or select a primary language."
        case .unsupportedLanguage(let language, let backend):
            "\(backend) does not support \(LanguageDetection.name(language)). Choose another transcription model."
        }
    }
}

actor LanguageDetection {
    static let shared = LanguageDetection()
    private let ear = Ear(directory: BundledModels.path("Ear"))
    private var tongue: Tongue?

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // Base language options; support is validated for the selected backend.
    static let choices = ["ar", "bg", "bn", "cs", "da", "de", "el", "en", "es", "et", "fa", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "lt", "lv", "ms", "mt", "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "ta", "th", "tr", "uk", "ur", "vi", "zh"]
        .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }

    static let detectionInterval = 30.0

    /// Sample at the detector's trained context length. Sustained evidence is
    /// required before switching away from the primary or established language.
    func regions(_ url: URL, language: String, status: @escaping @Sendable (String?) -> Void) async throws -> [LanguageRegion] {
        guard ear.isDownloaded() else { throw BundledModels.missing("Ear") }
        status("Detecting language changes…")
        let samples = try Pipeline.decodeMono(url, sampleRate: 16_000)
        guard !samples.isEmpty else { throw PipelineError.emptyAudio }
        let duration = Double(samples.count) / 16_000
        let cell = Int(Self.detectionInterval * 16_000)
        var regions: [LanguageRegion] = []
        for start in stride(from: 0, to: samples.count, by: cell) {
            try Task.checkCancellation()
            let end = min(start + cell, samples.count)
            let low = start
            let high = end
            let window = Array(samples[low..<high])
            // Silence has no language; inherit a neighbouring speech region below.
            let energy = window.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(window.count)
            let detection: (language: String?, confidence: Double, isReliable: Bool)?
            do {
                if energy > 0.000001 {
                    let result = try await ear.identify(samples: window, sampleRate: 16_000, windows: 1)
                    detection = (result.language, result.confidence, result.isReliable)
                } else { detection = nil }
            } catch {
                throw OptionsError("Ear language detection failed: \(error.localizedDescription) (\(String(reflecting: error)))")
            }
            regions.append(LanguageRegion(start: Double(start) / 16_000, end: min(duration, Double(end) / 16_000),
                                          language: detection?.isReliable == true && (detection?.confidence ?? 0) >= 0.8 ? detection?.language : nil,
                                          confidence: energy <= 0.000001 ? -1 : (detection?.confidence ?? 0)))
            status("Detecting languages · \(Transcript.clock(Double(end) / 16_000)) / \(Transcript.clock(duration))")
        }
        return Self.stabilize(regions, primary: language)
    }

    /// Two consecutive 30-second observations must agree before a switch.
    /// Confirmed switches are backdated to the first supporting window.
    static func stabilize(_ observations: [LanguageRegion], primary: String) -> [LanguageRegion] {
        var current: String? = primary == "auto" ? nil : primary
        var pending: String?
        var count = 0
        var result: [LanguageRegion] = []
        for observation in observations {
            let candidate = observation.language.flatMap { choices.contains($0) ? $0 : nil }
            if current == nil { current = candidate }
            if let candidate, candidate != current {
                if pending == candidate { count += 1 } else { pending = candidate; count = 1 }
                if count >= 2 {
                    current = candidate
                    for index in result.indices.suffix(count - 1) { result[index] = LanguageRegion(start: result[index].start,
                        end: result[index].end, language: candidate, confidence: observation.confidence, source: observation.source) }
                    pending = nil
                    count = 0
                }
            } else { pending = nil; count = 0 }
            result.append(LanguageRegion(start: observation.start, end: observation.end, language: current,
                confidence: candidate == current ? max(0, observation.confidence) : 0,
                source: candidate == current ? observation.source : "primary-or-held"))
        }
        return merge(result)
    }

    static func merge(_ regions: [LanguageRegion]) -> [LanguageRegion] {
        var merged: [LanguageRegion] = []
        for region in regions {
            if let previous = merged.last, previous.language == region.language {
                merged[merged.count - 1] = LanguageRegion(start: previous.start, end: region.end,
                    language: region.language, confidence: min(previous.confidence, region.confidence), source: region.source)
            } else { merged.append(region) }
        }
        return merged
    }

    /// Tongue checks text locally in short stretches, so a second language
    /// doesn't disappear inside the dominant language of a long transcript.
    func check(words: [Word], regions: [LanguageRegion], primary: String = "auto") throws -> (regions: [LanguageRegion], warnings: [String]) {
        if tongue == nil { tongue = try Tongue() }
        guard let tongue else { return (regions, []) }
        var checked: [LanguageRegion] = []
        var warnings: [String] = []
        var batches: [[Word]] = []
        var current: [Word] = []
        for word in words {
            if let first = current.first,
               word.end - first.start >= Self.detectionInterval {
                batches.append(current)
                current = []
            }
            current.append(word)
        }
        if !current.isEmpty { batches.append(current) }
        for batch in batches {
            guard let first = batch.first, let last = batch.last else { continue }
            let text = batch.map(\.text).joined()
            let detection = tongue.detect(text)
            let audioLanguage = regions.first { first.start >= $0.start && first.start < $0.end }?.language
            let textLanguage = detection.reliability == .confident && !detection.isTooCloseToCall ? detection.language : nil
            checked.append(LanguageRegion(start: first.start, end: last.end,
                                          language: textLanguage ?? audioLanguage, confidence: detection.candidates.first?.probability ?? 0,
                                          source: textLanguage == nil ? "audio" : "text"))
            if let textLanguage, let audioLanguage, textLanguage != audioLanguage {
                warnings.append("Language changes or detection disagreement near \(Transcript.clock(first.start)): audio \(Self.name(audioLanguage)), text \(Self.name(textLanguage)).")
            }
        }
        return (Self.stabilize(checked, primary: primary), Array(Set(warnings)).sorted())
    }
}
