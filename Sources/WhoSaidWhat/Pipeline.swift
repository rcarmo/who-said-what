import AVFoundation
import Foundation
import Speech
import Voz
import Who

struct Word: Sendable {
    let text: String
    let start: Double
    let end: Double
}

/// One speaker's uninterrupted stretch of speech. Keeps its words so exports can split it by time.
struct Segment: Identifiable {
    let id = UUID()
    var speaker: Int
    var words: [Word]

    var start: Double { words.first?.start ?? 0 }
    var end: Double { words.last?.end ?? 0 }
    var text: String { words.map(\.text).joined().trimmingCharacters(in: .whitespaces) }
}

enum Stage: Equatable {
    case idle
    case preparing
    case working(diarize: Double, transcribe: Double)
    case done
    case failed(String)
}

struct PreparedAudio {
    let url: URL
    let warnings: [String]
}

/// Runs Who (who spoke when) and the selected transcriber side by side, then
/// assigns every transcribed word to the speaker turn it falls in.
enum Pipeline {
    static let who = Who(directory: BundledModels.path("Who"))

    static func prepareAudio(for url: URL) async throws -> PreparedAudio {
        let audio = try await playableAudio(for: url)
        do {
            let file = try AVAudioFile(forReading: audio)
            let decoded = Double(file.length) / file.processingFormat.sampleRate
            var warnings: [String] = []
            if audio != url, let declared = try? await AVURLAsset(url: url).load(.duration),
               declared.seconds.isFinite, declared.seconds - decoded > 2 {
                warnings.append("Partial recording: recovered \(Transcript.clock(decoded)) of the advertised \(Transcript.clock(declared.seconds)). The source may be truncated or have an invalid sample index.")
            }
            return PreparedAudio(url: audio, warnings: warnings)
        } catch {
            if audio != url { try? FileManager.default.removeItem(at: audio) }
            throw error
        }
    }

    /// AVAudioFile reads wav/aiff/mp3/m4a/caf directly; anything else (video, odd containers)
    /// gets its audio track decoded to a temporary PCM file first (no lossy re-encode).
    static func playableAudio(for url: URL) async throws -> URL {
        // AVAudioFile can open AAC inside an MP4 while later PCM conversion
        // fails with Core Audio -50. Normalize movie containers before inference.
        let movieContainers: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi"]
        if let source = try? AVAudioFile(forReading: url) {
            if !movieContainers.contains(url.pathExtension.lowercased()) { return url }
            // AudioFile handles edit lists in some long meeting MP4s that
            // AVAssetReader rejects with -50 / invalid sample cursor errors.
            do { return try copyPCM(source) }
            catch is CancellationError { throw CancellationError() }
            catch { return try await AudioDecoder.decode(url) }
        }
        let failure = NSError(domain: "WhoSaidWhat", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Can't read audio from \(url.lastPathComponent)"])
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw failure }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw failure }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: out) } }
        var file: AVAudioFile?
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description = sample.formatDescription,
                  let asbd = description.audioStreamBasicDescription else { continue }
            var streamDescription = asbd
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else { throw failure }
            if file == nil {
                file = try AVAudioFile(forWriting: out, settings: format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: true)
            }
            let frames = AVAudioFrameCount(sample.numSamples)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw failure }
            buffer.frameLength = frames
            try sample.copyPCMData(fromRange: 0..<sample.numSamples, into: buffer.mutableAudioBufferList)
            try file?.write(from: buffer)
        }
        if reader.status == .failed { throw reader.error ?? failure }
        guard file != nil else { throw failure }
        complete = true
        return out
    }

    private static func copyPCM(_ input: AVAudioFile) throws -> URL {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        do {
            let format = input.processingFormat
            let output = try AVAudioFile(forWriting: out, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { throw PipelineError.emptyAudio }
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer, frameCount: AVAudioFrameCount(min(65_536, input.length - input.framePosition)))
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }

    /// Returns the result and the seconds the model itself took (download and decoding excluded).
    static func diarize(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (Diarization, Double) {
        try Task.checkCancellation()
        guard who.isDownloaded() else { throw BundledModels.missing("Who") }
        progress(0.5)
        // Decode up front so the timing below covers only the model.
        let samples = try decodeMono(url, sampleRate: 16_000)
        try Task.checkCancellation()
        let clock = ContinuousClock.now
        // Filter noise, but cap the cutoff at two seconds so a brief guest in
        // a long meeting isn't discarded merely for speaking under 2% of it.
        let result: Diarization
        do {
            let raw = try await who.diarize(samples: samples, sampleRate: 16_000)
            result = filterNoiseSpeakers(raw)
        } catch {
            throw OptionsError("Who speaker labelling failed: \(error.localizedDescription) (\(String(reflecting: error)))")
        }
        try Task.checkCancellation()
        let seconds = (ContinuousClock.now - clock).seconds
        progress(1)
        return (result, seconds)
    }

    static func filterNoiseSpeakers(_ result: Diarization) -> Diarization {
        result.keepingSpeakers(minimumShare: min(0.02, 2 / max(1, result.duration)))
    }

    static func decodeMono(_ url: URL, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw NSError(domain: "WhoSaidWhat", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Can't convert \(url.lastPathComponent) to mono"])
        }
        let chunk: AVAudioFrameCount = 65_536
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
        let output = AVAudioPCMBuffer(pcmFormat: target,
                                      frameCapacity: AVAudioFrameCount(Double(chunk) * sampleRate / file.processingFormat.sampleRate) + 1024)!
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * sampleRate / file.processingFormat.sampleRate))
        var finished = false
        var readError: Error?
        while true {
            try Task.checkCancellation()
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                if finished { outStatus.pointee = .endOfStream; return nil }
                if file.framePosition >= file.length { finished = true; outStatus.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: input, frameCount: AVAudioFrameCount(min(AVAudioFramePosition(chunk), file.length - file.framePosition)))
                } catch { readError = error; finished = true; outStatus.pointee = .endOfStream; return nil }
                if input.frameLength == 0 { finished = true; outStatus.pointee = .endOfStream; return nil }
                outStatus.pointee = .haveData
                return input
            }
            if let error { throw error }
            if let readError { throw readError }
            samples.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
            if status == .endOfStream || (status == .inputRanDry && finished) { break }
        }
        return samples
    }

    /// Returns words and inference time, excluding model downloads and loading.
    static func transcribe(_ url: URL, duration: Double, backend: TranscriptionBackend = .apple, language: String = "auto",
                           status: @escaping @Sendable (String?) -> Void = { _ in },
                           progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        try Task.checkCancellation()
        let regions = try await LanguageDetection.shared.regions(url, language: language, status: status)
        let result: ([Word], Double)
        var coverageWarnings: [String] = []
        switch backend {
        case .apple:
            var words: [Word] = []
            var seconds = 0.0
            for region in regions {
                guard let code = region.language else { throw PipelineError.uncertainLanguage(region.start) }
                let offset = max(0, region.start - 0.4)
                let end = min(duration, region.end + 0.4)
                let audio = regions.count == 1 ? url : try audioSlice(url, start: offset, end: end)
                defer { if audio != url { try? FileManager.default.removeItem(at: audio) } }
                let (part, took) = try await transcribeApple(audio, duration: end - offset, language: code, status: status) { p in
                    progress(min(0.99, (region.start + p * (region.end - region.start)) / duration))
                }
                // Overlap gives each recognizer context without duplicating words.
                words = appendAppleRegion(part, to: words, offset: offset, region: region, duration: duration)
                seconds += took
            }
            result = (words, seconds)
        case .voz:
            // Ear can confuse neighbouring languages in short meeting excerpts.
            // In auto mode its coverage findings are advisory, rather than an
            // excuse to abort the selected multilingual decoder.
            if language != "auto" {
                try LocalTranscribers.validateVozLanguages([LanguageRegion(start: 0, end: duration, language: language, confidence: 1)])
            }
            if regions.contains(where: { $0.language.map { !Voz.supportedLanguages.contains($0) } ?? false }) {
                coverageWarnings.append("Ear detected possible speech outside Voz's 25-language coverage. Review those sections or use another backend; automatic language detection can confuse related languages.")
            }
            result = try await LocalTranscribers.shared.voz(url, status: status, progress: progress)
        }
        try Task.checkCancellation()
        status("Checking transcript languages with Tongue…")
        let checked = try await LanguageDetection.shared.check(words: result.0, regions: regions, primary: language)
        var warnings = checked.warnings
        warnings += coverageWarnings
        if regions.contains(where: { $0.language == nil }) {
            warnings.append("Some audio language detections were uncertain; review those sections for accuracy.")
        }
        status(nil)
        progress(1)
        return TranscriptionOutput(words: result.0, seconds: result.1, languages: checked.regions, warnings: warnings)
    }

    private static func transcribeApple(_ url: URL, duration: Double, language: String,
                                        status: @escaping @Sendable (String?) -> Void,
                                        progress: @escaping @Sendable (Double) -> Void) async throws -> ([Word], Double) {
        status("Preparing Apple Speech…")
        let locale = try await AppleSpeech.locale(for: language)
        let transcriber = AppleSpeech.transcriber(locale: locale)
        try await AppleSpeech.ensureReady(transcriber, locale: locale, status: status)
        try Task.checkCancellation()
        status(nil)
        let clock = ContinuousClock.now
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        let collector = Task { () throws -> [Word] in
            var words: [Word] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters)
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    words.append(Word(text: text, start: range.start.seconds, end: range.end.seconds))
                }
                if duration > 0 { progress(min(1, result.range.end.seconds / duration)) }
            }
            return words
        }

        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let words = try await collector.value
            try Task.checkCancellation()
            progress(1)
            return (words, (ContinuousClock.now - clock).seconds)
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    static func appendAppleRegion(_ part: [Word], to previous: [Word], offset: Double,
                                  region: LanguageRegion, duration: Double) -> [Word] {
        var owned = part.map { Word(text: $0.text, start: $0.start + offset, end: min(duration, $0.end + offset)) }
            .filter { ($0.start + $0.end) / 2 >= region.start && ($0.start + $0.end) / 2 < region.end }
        // Each locale starts a fresh recognizer, which may omit its leading space.
        if let last = previous.last?.text.last, !last.isWhitespace,
           let first = owned.first, let head = first.text.first, !head.isWhitespace {
            owned[0] = Word(text: " " + first.text, start: first.start, end: first.end)
        }
        return previous + owned
    }

    /// Lossless, bounded-memory slice used when Apple Speech changes locale.
    static func audioSlice(_ url: URL, start: Double, end: Double) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        do {
            let output = try AVAudioFile(forWriting: out, settings: format.settings)
            input.framePosition = min(input.length, AVAudioFramePosition(start * format.sampleRate))
            var remaining = min(input.length, AVAudioFramePosition(end * format.sampleRate)) - input.framePosition
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { throw PipelineError.emptyAudio }
            while remaining > 0 {
                try Task.checkCancellation()
                try input.read(into: buffer, frameCount: AVAudioFrameCount(min(65_536, remaining)))
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }

    /// Each word goes to the turn that overlaps it most, or the nearest turn when it
    /// falls in a gap; consecutive words by the same speaker become one segment.
    static func align(words: [Word], turns: [Turn]) -> [Segment] {
        guard !turns.isEmpty else { return words.isEmpty ? [] : [Segment(speaker: 0, words: words)] }
        var segments: [Segment] = []
        for word in words {
            let speaker = bestSpeaker(for: word, in: turns)
            if let last = segments.last, last.speaker == speaker, word.start - last.end < 1.5 {
                segments[segments.count - 1].words.append(word)
            } else {
                segments.append(Segment(speaker: speaker, words: [word]))
            }
        }
        return segments
    }

    static func renumber(_ segments: [Segment]) -> [Segment] {
        var mapping: [Int: Int] = [:]
        return segments.map { segment in
            if mapping[segment.speaker] == nil { mapping[segment.speaker] = mapping.count }
            var segment = segment
            segment.speaker = mapping[segment.speaker]!
            return segment
        }
    }

    private static func bestSpeaker(for word: Word, in turns: [Turn]) -> Int {
        var best: (speaker: Int, overlap: Double)?
        for turn in turns {
            let overlap = min(word.end, turn.end) - max(word.start, turn.start)
            if overlap > 0, overlap > (best?.overlap ?? 0) { best = (turn.speaker, overlap) }
        }
        if let best { return best.speaker }
        let mid = (word.start + word.end) / 2
        return turns.min { distance(mid, $0) < distance(mid, $1) }!.speaker
    }

    private static func distance(_ t: Double, _ turn: Turn) -> Double {
        t < turn.start ? turn.start - t : (t > turn.end ? t - turn.end : 0)
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
