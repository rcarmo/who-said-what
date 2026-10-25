import AVFoundation
import Foundation
import Testing
import Who
@testable import WhoSaidWhat

struct TranscriptionTests {
    @Test func appleLocaleSeamsKeepOriginalTimesAndWordSpacing() {
        let previous = [Word(text: " Hola.", start: 29, end: 29.5)]
        let part = [Word(text: "Hola.", start: 0, end: 0.2),
                    Word(text: "Hello", start: 0.5, end: 1),
                    Word(text: " again", start: 1, end: 1.5)]
        let result = Pipeline.appendAppleRegion(part, to: previous, offset: 29.6,
            region: LanguageRegion(start: 30, end: 60, language: "en", confidence: 1), duration: 60)
        #expect(result.map(\.text).joined() == " Hola. Hello again")
        #expect(result.count == 3)
        #expect(abs(result[1].start - 30.1) < 0.0001)
        #expect(abs(result.last!.end - 31.1) < 0.0001)
    }

    @Test func applePrefersInstalledVariantOfBaseLanguage() {
        let supported = [Locale(identifier: "en_US"), Locale(identifier: "en_GB"),
                         Locale(identifier: "it_CH"), Locale(identifier: "it_IT"), Locale(identifier: "es_ES")]
        #expect(AppleSpeech.chooseLocale(language: "en", supported: supported,
            installed: [Locale(identifier: "en-GB")])?.identifier == "en_GB")
        #expect(AppleSpeech.chooseLocale(language: "it", supported: supported, installed: [])?.identifier == "it_IT")
        #expect(AppleSpeech.chooseLocale(language: "ja", supported: supported, installed: []) == nil)
    }

    @Test func mp4AudioIsNormalizedBeforeInference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wav = root.appendingPathComponent("source.wav")
        let movie = root.appendingPathComponent("recording.mp4")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) / 10)) * 0.2 }
        do { let file = try AVAudioFile(forWriting: wav, settings: format.settings); try file.write(from: buffer) }
        let exporter = AVAssetExportSession(asset: AVURLAsset(url: wav), presetName: AVAssetExportPresetAppleM4A)!
        try await exporter.export(to: movie, as: .m4a)
        let prepared = try await Pipeline.playableAudio(for: movie)
        defer { if prepared != movie { try? FileManager.default.removeItem(at: prepared) } }
        #expect(prepared != movie)
        #expect(prepared.pathExtension == "caf")
        let samples = try Pipeline.decodeMono(prepared, sampleRate: 16_000)
        #expect(samples.count >= 15_900)
        #expect(samples.contains { abs($0) > 0.1 })
    }

    @Test func decoderHandlesEOFWithoutLosingTheLastSamples() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        for i in 0..<1_600 { buffer.floatChannelData![0][i] = 0.25 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let samples = try Pipeline.decodeMono(url, sampleRate: 16_000)
        #expect(samples.count == 1_600)
        #expect(samples.last == 0.25)
    }
    @Test func modelWordsKeepSpacesAndBoundedTimes() {
        let words = LocalTranscribers.spacedWords([
            Word(text: "Olá,", start: 0.1, end: 0.4),
            Word(text: "world!", start: 0.8, end: 3),
            Word(text: "invalid", start: .nan, end: 2)
        ], duration: 1.2)
        #expect(Segment(speaker: 0, words: words).text == "Olá, world!")
        #expect(words.last?.end == 1.2)
    }

    @Test func wordsFollowSpeakersInsideASentence() {
        let words = [Word(text: " Hello", start: 0.2, end: 0.5), Word(text: " Olá", start: 1.2, end: 1.5)]
        let turns = [Turn(start: 0, end: 1, speaker: 3), Turn(start: 1, end: 2, speaker: 1)]
        let segments = Pipeline.renumber(Pipeline.align(words: words, turns: turns))
        #expect(segments.map(\.speaker) == [0, 1])
        #expect(segments.map(\.text) == ["Hello", "Olá"])
    }

    @Test func briefGuestsSurviveInLongMeetings() {
        let raw = Diarization(turns: [Turn(start: 0, end: 14_000, speaker: 0),
                                     Turn(start: 14_010, end: 14_020, speaker: 1),
                                     Turn(start: 14_030, end: 14_030.2, speaker: 2)], duration: 14_400)
        let filtered = Pipeline.filterNoiseSpeakers(raw)
        #expect(filtered.speakerCount == 2)
        #expect(filtered.turns.contains { $0.speaker == 1 && $0.duration == 10 })
    }

    @Test func vttContainsEscapedSpeakerAttributions() {
        let transcript = Transcript(fileName: "test.wav", duration: 4,
            segments: [Segment(speaker: 0, words: [Word(text: " Olá <team> & friends", start: 0.25, end: 1.5)]),
                       Segment(speaker: 1, words: [Word(text: " Hello", start: 2, end: 3)])],
            names: [0: "Ana & <Host>\n", 1: "Guest"], warnings: ["Partial recording: missing audio."])
        let vtt = transcript.render(.vtt)
        #expect(vtt.hasPrefix("WEBVTT\n\n"))
        #expect(vtt.contains("NOTE Partial recording: missing audio.\n\n"))
        #expect(vtt.contains("00:00:00.250 --> 00:00:01.500\n<v Ana &amp; &lt;Host&gt;>Olá &lt;team&gt; &amp; friends</v>"))
        #expect(vtt.contains("<v Guest>Hello</v>"))
        #expect(!vtt.contains("<team>"))
    }

    @Test func languageChangesArePreserved() throws {
        let regions = LanguageDetection.merge([
            LanguageRegion(start: 0, end: 4, language: "en", confidence: 0.9),
            LanguageRegion(start: 4, end: 8, language: "pt", confidence: 0.95),
            LanguageRegion(start: 8, end: 12, language: "pt", confidence: 0.9),
            LanguageRegion(start: 12, end: 16, language: "en", confidence: 0.8)
        ])
        #expect(regions.map(\.language) == ["en", "pt", "en"])
        #expect(regions[1].end == 12)
        try LocalTranscribers.validateVozLanguages(regions)
        #expect(throws: PipelineError.self) {
            try LocalTranscribers.validateVozLanguages([LanguageRegion(start: 0, end: 4, language: "ja", confidence: 0.99)])
        }
    }

    @Test func cliSelectsBackendLanguageAndVTTFile() throws {
        let options = try CommandLineOptions(["WhoSaidWhat", "--print", "/tmp/episode.wav", "--backend", "voz",
            "--output", "/tmp/episode.vtt", "--names", "Host,,Guest", "--language", "auto"])
        #expect(options.backend == .voz)
        #expect(options.language == "auto")
        #expect(options.format == .vtt)
        #expect(options.names[2] == "Guest")
        #expect(throws: OptionsError.self) { try CommandLineOptions(["app", "--print", "in.wav", "--backend", "typo"]) }
        #expect(throws: OptionsError.self) { try CommandLineOptions(["app", "--print", "in.wav", "--backend", "nemotron"]) }
        #expect(throws: OptionsError.self) { try CommandLineOptions(["app", "--print", "in.wav", "--output", "in.wav"]) }
    }

    @Test func tongueChecksChangesWithinOneTranscript() async throws {
        let english = "The people in this room are discussing the future of public transport and how we can make our cities better places to live for everyone today and tomorrow."
        let portuguese = "As pessoas nesta sala estão a discutir o futuro dos transportes públicos e como podemos tornar as nossas cidades melhores lugares para viver para todos hoje e amanhã."
        let speech = Array(repeating: english, count: 4).joined(separator: " ") + " " + Array(repeating: portuguese, count: 10).joined(separator: " ")
        let words = speech.split(separator: " ").enumerated().map {
            Word(text: " " + $0.element, start: Double($0.offset) * 0.3, end: Double($0.offset + 1) * 0.3)
        }
        let checked = try await LanguageDetection.shared.check(words: words, regions: [])
        let languages = Set(checked.regions.compactMap(\.language))
        #expect(languages.contains("en"))
        #expect(languages.contains("pt"))
    }

    @Test func primaryLanguageIgnoresBriefFalseSwitches() throws {
        let codes = ["es", "pt", "es", "en", "en", "es", "en"]
        let observations = codes.enumerated().map {
            LanguageRegion(start: Double($0.offset) * 30, end: Double($0.offset + 1) * 30, language: $0.element, confidence: 0.99)
        }
        let stable = LanguageDetection.stabilize(observations, primary: "es")
        #expect(stable.map(\.language) == ["es", "en"])
        #expect(stable[1].start == 90)
        #expect(LanguageDetection.detectionInterval == 30)
        #expect(LanguageDetection.choices.contains("it"))
        #expect(LanguageDetection.choices.allSatisfy { !$0.contains("-") && !$0.contains("_") })
        let options = try CommandLineOptions(["app", "--print", "in.wav", "--primary-language", "it"])
        #expect(options.language == "it")
    }
}
