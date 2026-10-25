# Local benchmark — 25 October 2026

Hardware: Apple M3 Max, 36 GiB unified memory, macOS 27.0.1.

The supplied workshop MP4 advertises 04:00:00, but its sample index references packets beyond the end of the physical file. The bundled decoder recovers **02:57:26.656**. All successful speed calculations below use that recovered duration, not the advertised four hours. The source recording and generated transcripts are excluded from Git.

Each backend runs in a separate process, sequentially, with network access denied by `sandbox-exec`. Models and the standalone audio decoder are loaded from the app bundle. This is a practical single-pass benchmark; system caches are not reset between runs.

| Backend | Overall wall time | ASR time | Overall speed | Peak RSS | Attributed VTT cues |
| --- | ---: | ---: | ---: | ---: | ---: |
| Voz | 187.982 s | 81.37 s | 56.64× realtime | 1,640.5 MiB | 1,858 / 1,858 |
| Apple Speech | 140.282 s | 122.33 s | 75.89× realtime | 1,481.9 MiB | 1,634 / 1,634 |

Voz produced 18,281 timed words and 12 diarization labels. Its last subtitle ends at 02:57:24.980, within the recovered audio. Every VTT cue carries a `<v Speaker N>` attribution, and each file begins with a `NOTE` explaining the partial source recording.

Apple initially lacked the Spanish assets. After provisioning system-managed English, Spanish and Italian assets, it completed a full offline pass with a Spanish primary-language hint: 14,132 timed words and 12 diarization labels. All 1,634 cues carry attribution and its last subtitle ends at 02:57:25.580. Runtime Apple asset downloads are now allowed when needed; the measured pass used installed assets and denied networking. Separate English, Spanish, Italian and Portuguese smoke tests passed. A French smoke test exercised the runtime download path for a missing Apple language, then succeeded with networking denied. A repeated-speech English/Spanish/Italian fixture completed offline and retained original timestamps, but its Spanish section also exposed the routing limitation; completing a multilingual run is not an accuracy pass. The generated Italian fixture checks functionality, not human-speech accuracy. See the [Apple/Voz output comparison](APPLE_VOZ_COMPARISON.md) for serious quality limitations on this recording.

Overall wall time includes audio recovery, language detection, model initialization, diarization, transcription, language checking and export. ASR time excludes ASR model loading. Who's 151.84-second time on the first full pass includes its SDK's lazy model initialization. Apple's Who pass took 84.16 seconds. Cache state was not controlled, so overall wall times are single-pass observations rather than a fair isolated ASR speed ranking. Voz's ASR stage took 81.37 seconds versus Apple's 122.33 seconds; per-model timers still have different preparation boundaries.

Language tracking uses base languages and an optional primary-language hint. Ear samples at 30-second intervals and changes require two agreeing observations. Tongue checks transcript text at the same cadence. Voz's multilingual decoder operates independently of these conservative labels. Short language switches may be transcribed without changing the stabilized language label.

Word counts and detected speaker counts are descriptive outputs, not accuracy scores. No reference transcript or verified speaker annotation was supplied, so WER and diarization error rate are not reported.

Reproduce with:

```sh
python3 Tools/benchmark.py recording.mp4 --app WhoSaidWhat.app --output benchmarks/full --backends voz
python3 Tools/benchmark.py recording.mp4 --app WhoSaidWhat.app --output benchmarks/full-apple --backends apple --primary-language es
```

Detailed logs, timing JSON and attributed VTTs for Voz are in `benchmarks/full/`; the later Apple pass is in `benchmarks/full-apple/`. The benchmark script validates that every exported cue has a speaker attribution and uses the decoded duration reported by the app.

## Validation

All 12 current regression tests pass. Both supported backends' full VTTs have chronological cue starts, positive cue durations bounded by the recovered audio, a named voice on every cue, and a partial-recording note. After removing the retired backend, a relocated 431 MiB app completed the two-minute workshop excerpt with networking and project `.build` reads denied: Voz produced 26 attributed cues and Apple produced 24. The app contains only Who/Voz/Ear model directories and Tongue/usage SDK resource bundles.

The retired Nemotron backend's earlier logs and VTT remain in the ignored benchmark directory as historical results. It is no longer selectable, linked or bundled. For quality findings on the remaining backends, see the [Apple/Voz comparison](APPLE_VOZ_COMPARISON.md).
