# Windows feasibility — 25 October 2026

A Windows version can provide the Voz-based feature set: local transcription, speaker attribution, language changes during a recording, a base-language selector including Italian, media playback, speaker renaming, and TXT/SRT/attributed VTT/JSON export. This is a port, not a recompilation of the current macOS app. No Windows build or performance validation has been performed here.

## What can be retained

| Feature | Windows path | Main difference |
| --- | --- | --- |
| Voz transcription and word timestamps | Desert Ant's Windows Swift SDK, ONNX Runtime + DirectML | Windows ONNX weights replace the bundled Apple Core ML graphs; GPU performance must be measured. |
| Who speaker diarization | The same SDK API, LiteRT on CPU | Windows uses the published INT8 model; current Mac packaging uses its Apple model. Small numerical/precision differences are expected. |
| Ear spoken-language detection | Windows SDK / LiteRT | Retain the application's 30-second windows and sustained-evidence policy; test the same meeting audio. |
| Tongue text-language checking | Windows SDK with bundled weights | Retain checking cadence and disagreement warnings. |
| Primary language, Italian, changing languages | Reuse the base-language data and detection policy | Detection remains imperfect; porting does not fix the existing routing limitations. |
| Speaker names, alignment, VTT/TXT/SRT/JSON | Extract the platform-independent Swift data/export code | Preserve `<v Speaker Name>` tags, escaping and timestamps. |
| Drag/drop, player, timeline, progress, cancellation | Rebuild the SwiftUI/AppKit UI with WinUI 3 | Replace AVPlayer/AVFoundation with Windows playback and a local audio decoder. |
| Bundled models, no runtime model fetches | Fetch Windows-specific artifacts during packaging and ship them with runtime DLLs | Use explicit model directories, preflight assets and verify under blocked networking. |
| Apple Speech backend | Unavailable on Windows | A second local backend would need a separate implementation and validation. |

The documented Windows SDK baseline is **x64 with Swift 6.2+**. Windows ARM64 should be treated as a separate validation target rather than promised from the SDK's current platform table. [SDK platform support](https://github.com/Desert-Ant-Labs/desert-ant-core#platform-support)

[Voz's Windows documentation](https://desertant.com/docs/voz/#windows) explicitly describes ONNX Runtime/DirectML GPU execution. [Who's documentation](https://desertant.com/docs/who/#linux-and-windows) describes the Windows LiteRT CPU backend and its 8-bit weights. [Ear](https://desertant.com/docs/ear/) and [Tongue](https://desertant.com/docs/tongue/) list Windows support. Those establish a supported implementation path, not this application's tested Windows quality or speed.

## Suggested implementation

Keep the Mac UI native. Extract a shared Swift core containing transcript data, speaker alignment, language stabilization, export, and SDK-facing inference. Create a Windows command-line worker around that core, with structured progress/results and cancellation. A C# / WinUI 3 application can launch the worker and handle file selection, drag/drop, playback, speaker editing and export dialogs. This reuses the supported Windows inference SDK without requiring the C# UI to call Swift objects directly.

Build and bundle a Windows FFmpeg executable for audio normalization and malformed-container recovery, plus all SDK/runtime dependencies and the Windows model variants. The current macOS decoder binary and `.mlmodelc` assets cannot simply be copied across. Preserve notices/source obligations in the Windows package as in the Mac package.

The existing Apple option cannot be reproduced literally. Microsoft's newer local batch/streaming Speech Recognition API is currently marked **experimental and unsupported for production**, and requires recent Windows 11/Windows App SDK versions. It is therefore a candidate to investigate, not a production-equivalent replacement to promise. [Microsoft Speech Recognition documentation](https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition)

The first deliverable should be a Windows x64 inference worker tested on the supplied recording, followed by the native UI. Validate speaker continuity, short language switches, Italian, cancellation, malformed media recovery, attributed VTT, offline launch and bundled dependencies. Benchmark at least an integrated-GPU PC and the intended deployment hardware before setting speed/memory requirements. The M3 Max timings do not predict Windows performance.
