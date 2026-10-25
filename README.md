# Who Said What

A macOS app for speaker-attributed, multilingual transcripts. Drop an audio or video recording, select a transcription model, then play, rename speakers and export TXT, SRT, attributed WebVTT or JSON. Processing stays on your Mac.

![Who Said What](docs/demo.gif)

## Transcription models

| Option | Runtime | Language handling |
| --- | --- | --- |
| **Voz — Desert Ant Labs** (default) | Core ML / Neural Engine | Multilingual decoding across 25 European languages; warns about possible speech outside its coverage; rejects unsupported manual language selections |
| **Apple Speech** | macOS SpeechTranscriber | Changes locale between detected language sections; macOS downloads missing language assets when needed |

All options run alongside [Who diarization](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/main/docs/models/who.md). Words are assigned to the speaker turn they overlap most. Consecutive words from one speaker become transcript paragraphs. Playback, the speaker timeline, renaming and all exports work with every backend.

## Languages that change during a recording

The **Primary language** selector uses base languages, including English, Spanish, Portuguese, French, German and Italian. It is a fallback hint rather than a fixed recording-wide locale. Its default **Auto** setting runs Desert Ant's [Ear](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/main/docs/models/ear.md) on local audio windows, rather than assigning one language to the whole recording. Ear analyzes non-overlapping 30-second windows. Two consecutive windows must agree before the established language changes; a confirmed switch is backdated to the first supporting window. Isolated guesses and silence keep the primary or established language. Adjacent sections in the same language are merged. Tongue checks transcript text at the same 30-second cadence, with the same stability rule.

Voz transcribes the recording with its multilingual decoder. Apple transcribes each detected section with the corresponding locale; short overlapping slices preserve context, and timestamps are translated back to the original recording. Apple stops with a clear error if the language is uncertain or unavailable instead of silently using English.

[Tongue](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/main/docs/models/tongue.md) then checks short stretches of transcript text. The results screen shows the languages found and flags disagreements between audio and text detection. JSON includes timestamped language regions. A selected primary language helps with short or ambiguous clips while multilingual decoding remains enabled. The selector uses base languages, not regional dialects.

**Voz is the recommended default for the tested English/Spanish workshop**: its sample output preserves more wording and technical terms, and its recognition stage runs faster. Voz decodes multilingual speech within a detected section. Apple uses one locale per detected section, so brief switches can be missed. See [local benchmark results](docs/BENCHMARKS.md) and the [Apple/Voz comparison](docs/APPLE_VOZ_COMPARISON.md). Local window detection can miss very brief switches, and language identification is imperfect on short, noisy or distant speech. Tongue is a consistency check, not proof that a transcript is correct.

## Self-contained model packaging

`build_app.sh` fetches model weights at **build time** and copies them into `WhoSaidWhat.app/Contents/Resources/Models`:

- Who: speaker diarization, pinned SDK model revision.
- Voz: multilingual transcription, pinned SDK model revision.
- Ear: spoken-language identification, pinned SDK model revision.
- Tongue: text-language weights in the SDK's resource bundle.

A small standalone FFmpeg audio decoder is also bundled. It handles meeting containers that Apple's native audio reader rejects, and is built with only the local file protocol enabled. Its LGPL license, source archive and build recipe travel with the app. Native decoding is used first, with the bundled decoder as a fallback.

The separate `BundleModels` build tool performs model downloads. It is **not included in the app**. The app uses explicit model directories, checks required assets and never downloads missing Voz, Who, Ear or Tongue models at runtime. Move the `.app` as a unit: its models and resource bundles travel with it. `Models/MODELS.txt` records model revisions; `.build/model-assets` caches packaging inputs for subsequent builds.

Apple's speech assets are managed by macOS and cannot be redistributed inside the app. Apple Speech downloads missing language assets through Apple's AssetInventory, with progress shown in the app. Once installed, transcription works offline while those system assets remain available. Bundled Voz needs no speech-asset installation. Desert Ant's SDK may still send its monthly license check (no audio); disabling model downloads does not disable the SDK's licensing behavior.

## Build and run

Requires macOS 26+, Apple Silicon and Xcode 26+ / Swift 6.2+. The first build needs network access to fetch Swift dependencies and model weights. Later model preparation reuses its local assets.

```sh
./build_app.sh
open WhoSaidWhat.app
open WhoSaidWhat.app --args -open /path/to/episode.mp4
```

Model loading and first-use Neural Engine specialization happen locally. Voz and the shared analysis models are bundled before the first transcription. Apple can download missing system assets at runtime. To prefetch languages explicitly, run `WhoSaidWhat.app/Contents/MacOS/WhoSaidWhat --install-apple-assets en,es,it`; the optional build variable `WHO_SAID_WHAT_APPLE_LANGUAGES=en,es,it` does the same on the build Mac.

### Command line and attributed WebVTT

```sh
# Multilingual transcription with speaker voice tags, written directly to a file:
WhoSaidWhat.app/Contents/MacOS/WhoSaidWhat \
  --print episode.mp4 --backend voz --primary-language auto \
  --names "Host,Guest" --output episode.vtt

# Voz, with stdout suitable for piping:
WhoSaidWhat.app/Contents/MacOS/WhoSaidWhat \
  --print episode.wav --backend voz --format vtt > episode.vtt

# Primary-language hint; language changes remain enabled:
WhoSaidWhat.app/Contents/MacOS/WhoSaidWhat \
  --print episode.wav --backend apple --primary-language pt --format json
```

`--backend` accepts `apple` or `voz`. `--primary-language` defaults to `auto` and accepts a base ISO language code such as `en`, `pt`, `fr` or `it`. `--language` remains an alias. `--output` infers the format from its extension; `--format` overrides it. Statistics and warnings go to stderr. Run `--help` for the full syntax.

VTT output contains named voice spans, with escaped text and names:

```vtt
WEBVTT

00:00:01.200 --> 00:00:04.800
<v Host>Welcome. Olá a todos!</v>
```

Voice tags preserve speaker attribution for WebVTT consumers. Some players do not display voice names visually. TXT and SRT use visible `Name: text` prefixes. Speaker names are assigned in order of first transcribed appearance and follow UI renames.

## Verification

```sh
swift test -c release
```

Twelve tests cover Apple locale selection and timestamp/spacing seams, AAC-in-MP4 normalization, PCM EOF handling, speaker alignment across a sentence, model word spacing, bounded timestamps, language changes and Voz coverage, CLI validation, and attributed VTT escaping. Real model smoke tests can use the packaged command line on local recordings without network access, after provisioning any Apple language assets needed.

```sh
python3 Tools/benchmark.py recording.mp4 --app WhoSaidWhat.app --output benchmarks
```

The benchmark runs backends sequentially with network access denied, validates voice attribution on every VTT cue, and records wall time, ASR time, Who time and peak resident memory. Wall time includes audio preparation, language detection and model initialization; Who time includes its SDK lazy initialization, while ASR time excludes ASR model loading. Compare wall time when evaluating end-to-end performance.

## Limitations

Who labels up to four speakers per five-minute section and works best on close-miked recordings. Very brief speakers or noises can be filtered out; synthetic voices are a poor diarization benchmark. Language changes need not coincide with speaker changes. Model accuracy and language support vary. A missing or uncertain language is surfaced to the user. Automatic Ear detections are advisory for Voz: related-language confusion does not abort a long recording. Apple requires a supported locale for each section and network access when its system assets are missing. Conservative language tracking can miss brief switches; Voz continues recognizing them independently.

## Windows feasibility

The Voz-based feature set can be ported to Windows, including bundled models, speaker attribution, changing-language detection, playback and VTT exports. The SwiftUI/AppKit/AVFoundation/Speech parts need Windows replacements. See the [Windows port assessment](docs/WINDOWS.md) for the supported SDK paths and remaining validation.

## Project layout

- `Sources/WhoSaidWhat/Transcription.swift`: backend choices and bundled native model adapters.
- `Sources/WhoSaidWhat/LanguageDetection.swift`: Ear section detection and Tongue checks.
- `Sources/WhoSaidWhat/Pipeline.swift`: audio preparation, Apple Speech, diarization and word/speaker alignment.
- `Sources/WhoSaidWhat/AudioDecoder.swift`: bundled offline audio-decoding fallback.
- `Sources/WhoSaidWhat/BundledModels.swift`: runtime model locations and missing-asset errors.
- `Sources/WhoSaidWhat/CommandLineOptions.swift`: validated CLI options.
- `Sources/WhoSaidWhat/ContentView.swift`: selection, progress, playback, speakers and exports.
- `Sources/WhoSaidWhat/Export.swift`: TXT, SRT, WebVTT and JSON.
- `Tools/BundleModels/`: build-time model downloader.
- `Tools/benchmark.py`: sequential offline benchmark; requires ffprobe and writes attributed VTT plus timing, memory and error logs.
- `Tests/WhoSaidWhatTests/`: regression tests.

## Licenses and attribution

The app remains demo code. Who, Voz, Ear, Tongue and the Desert Ant SDK use the [Desert Ant Labs Source-Available License](https://license.desertant.com/1.0). Voz derives from NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0). Upstream model and software licenses still apply; see `docs/THIRD_PARTY_NOTICES.txt` and the model cards included in the app.
