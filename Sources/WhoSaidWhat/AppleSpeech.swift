import Foundation
import Speech

enum AppleSpeech {
    // These are implementation choices for a base language, never extra picker entries.
    private static let preferredIDs = ["en": "en-US", "es": "es-ES", "it": "it-IT",
        "pt": "pt-PT", "fr": "fr-FR", "de": "de-DE", "zh": "zh-CN"]

    private static func identifier(_ locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    /// Prefer a model already on this Mac, even when its regional variant differs
    /// from the default. Return the framework's supported Locale object itself.
    static func chooseLocale(language: String, supported: [Locale], installed: [Locale]) -> Locale? {
        let candidates = supported.filter { $0.language.languageCode?.identifier == language }
            .sorted { identifier($0) < identifier($1) }
        let installedIDs = Set(installed.map(identifier))
        let ready = candidates.filter { installedIDs.contains(identifier($0)) }
        let preferred = (preferredIDs[language] ?? language).lowercased()
        return ready.first { identifier($0) == preferred } ?? ready.first
            ?? candidates.first { identifier($0) == preferred } ?? candidates.first
    }

    static func locale(for language: String) async throws -> Locale {
        guard let locale = chooseLocale(language: language, supported: await SpeechTranscriber.supportedLocales,
                                        installed: await SpeechTranscriber.installedLocales) else {
            throw PipelineError.unsupportedLanguage(language, TranscriptionBackend.apple.title)
        }
        return locale
    }

    static func transcriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    /// macOS manages these assets; only Apple's backend may download at runtime.
    static func ensureReady(_ module: SpeechTranscriber, locale: Locale,
                            status: @escaping @Sendable (String?) -> Void) async throws {
        if await AssetInventory.status(forModules: [module]) == .installed { return }
        let name = LanguageDetection.name(locale.language.languageCode?.identifier ?? locale.identifier)
        try Task.checkCancellation()
        status("Preparing Apple Speech assets for \(name)…")
        do {
            // Do not release another locale to evade the system reservation limit.
            try await AssetInventory.reserve(locale: locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                status("Downloading Apple Speech assets for \(name)…")
                let reporter = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled {
                            status(String(format: "Downloading Apple Speech %@: %.0f%%", name,
                                          request.progress.fractionCompleted * 100))
                        }
                    }
                }
                defer { reporter.cancel() }
                try await request.downloadAndInstall()
            }
            try Task.checkCancellation()
            guard await AssetInventory.status(forModules: [module]) == .installed else {
                throw OptionsError("The system has not finished installing the language assets.")
            }
        } catch {
            try Task.checkCancellation()
            throw OptionsError("Apple Speech could not prepare \(name) (\(locale.identifier)): \(error.localizedDescription) Try again with an Internet connection, or use a bundled backend.")
        }
        status(nil)
    }

    /// Optional prefetch, using the same installation path as normal transcription.
    static func install(languages: [String]) async throws {
        for language in languages {
            guard LanguageDetection.choices.contains(language) else { throw OptionsError("Unknown base language: \(language)") }
            let locale = try await locale(for: language)
            let module = transcriber(locale: locale)
            if await AssetInventory.status(forModules: [module]) == .installed {
                print("Apple Speech \(language): already installed (\(locale.identifier))")
                continue
            }
            try await ensureReady(module, locale: locale) { message in
                if let message { print(message) }
            }
            print("Apple Speech \(language): ready offline")
        }
    }
}
