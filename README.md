# Who Said What

A macOS app that turns audio and video recordings into transcripts with speaker labels. Drop a recording, play it back, rename speakers and export the transcript. Audio is processed on your Mac.

This fork of [Andris Gauracs's original app](https://github.com/andrisgauracs/who-said-what) adds Voz transcription, multilingual language selection, speaker-attributed WebVTT export and improved support for importing recordings.

![Who Said What](docs/demo.gif)

## Features

- **Voz** transcription by Desert Ant Labs, with **Apple Speech** as an alternative.
- Speaker labels, editable names, a speaker timeline and playback.
- Automatic language detection and a primary-language selector, including English, Spanish, Portuguese, French, German and Italian.
- Support for language changes during a recording. Voz is recommended for mixed-language recordings; Apple Speech can miss brief switches.
- TXT, SRT, WebVTT and JSON export. WebVTT preserves speaker attribution, although some players do not display speaker names.

## Build and run

Requires macOS 26+, Apple Silicon and Xcode 26+ / Swift 6.2+.

```sh
./build_app.sh
open WhoSaidWhat.app
```

The first build downloads dependencies and bundles the models with the app. Voz needs no model downloads during use. Apple Speech may download missing language assets from Apple.

Drop a recording onto the window, choose a transcription option and leave the primary language on **Auto**, or select a language as a hint. After transcription, rename speakers and export in your preferred format.

## Command line

```sh
WhoSaidWhat.app/Contents/MacOS/WhoSaidWhat \
  --print recording.mp4 --backend voz \
  --names "Host,Guest" --output transcript.vtt
```

Use `--backend apple` for Apple Speech or `--primary-language it` to select Italian as the primary-language hint. Run `--help` for all options.

## Licenses and attribution

Who, Voz, Ear, Tongue and the Desert Ant SDK use the [Desert Ant Labs Source-Available License](https://license.desertant.com/1.0). Voz derives from NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0). See the [third-party notices](docs/THIRD_PARTY_NOTICES.txt) for model and software attribution.
