import Foundation

struct CommandLineOptions {
    let input: URL
    let output: URL?
    let backend: TranscriptionBackend
    let language: String
    let format: ExportFormat
    let names: [Int: String]

    static let usage = """
    Usage: WhoSaidWhat --print FILE [--backend apple|voz]
                      [--primary-language auto|LANGUAGE_CODE] [--format txt|srt|vtt|json]
                      [--names "Host,Guest"] [--output transcript.vtt]

    Primary language is a base-language hint; changes remain enabled.
    Auto uses stable language detection (default). --language is an alias.
    --output infers the format from its extension unless --format is supplied.
    WebVTT includes speaker attributions using <v Speaker Name> voice tags.
    Without --output, the transcript is written to stdout.

    Optional prefetch: --install-apple-assets en,es,it
    Apple may download missing system language assets during transcription.
    Voz uses a bundled model without runtime downloads.
    """

    init(_ args: [String]) throws {
        var values: [String: String] = [:]
        let flags = ["--print", "--backend", "--language", "--primary-language", "--format", "--names", "--output"]
        var i = 1
        while i < args.count {
            let flag = args[i]
            guard flags.contains(flag), i + 1 < args.count, !args[i + 1].hasPrefix("--"), values[flag] == nil else {
                throw OptionsError("Unknown, duplicate, or incomplete argument: \(flag)")
            }
            values[flag] = args[i + 1]
            i += 2
        }
        guard let path = values["--print"] else { throw OptionsError("--print requires an audio or video file.") }
        input = URL(fileURLWithPath: path)
        output = values["--output"].map { URL(fileURLWithPath: $0) }
        guard output?.resolvingSymlinksInPath().standardizedFileURL != input.resolvingSymlinksInPath().standardizedFileURL else {
            throw OptionsError("The output must not overwrite the input recording.")
        }
        guard let selected = TranscriptionBackend(rawValue: values["--backend"] ?? "voz") else {
            throw OptionsError("--backend must be apple or voz.")
        }
        backend = selected
        guard values["--language"] == nil || values["--primary-language"] == nil else {
            throw OptionsError("Use either --primary-language or --language, not both.")
        }
        language = (values["--primary-language"] ?? values["--language"] ?? "auto").lowercased()
        guard language == "auto" || LanguageDetection.choices.contains(language) else {
            throw OptionsError("--language must be auto or a supported ISO language code, such as en, pt, or fr.")
        }
        let requestedFormat = values["--format"] ?? output?.pathExtension.lowercased() ?? "txt"
        guard let selectedFormat = ExportFormat.allCases.first(where: { [$0.rawValue, $0.fileExtension].contains(requestedFormat) }) else {
            throw OptionsError("The output format must be txt, srt, vtt, or json.")
        }
        format = selectedFormat
        var speakerNames: [Int: String] = [:]
        for (index, name) in (values["--names"] ?? "").split(separator: ",", omittingEmptySubsequences: false).enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { speakerNames[index] = trimmed }
        }
        names = speakerNames
    }
}

struct OptionsError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
