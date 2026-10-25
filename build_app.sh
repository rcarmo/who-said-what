#!/bin/zsh
# Builds WhoSaidWhat.app with bundled local models; Apple assets are system-managed.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
Tools/build_audio_decoder.sh
ln -sfn "$PWD/.build/audio-decoder/ffmpeg" "$BIN_DIR/ffmpeg"
MODEL_DIR="$PWD/.build/model-assets"
"$BIN_DIR/BundleModels" "$MODEL_DIR"
# Also make bundled assets available to the SwiftPM command-line executable.
ln -sfn "$MODEL_DIR" "$BIN_DIR/Models"

STAGING="$(mktemp -d "$PWD/.build/app-staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/WhoSaidWhat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Helpers"
cp "$BIN_DIR/WhoSaidWhat" "$APP/Contents/MacOS/"
cp .build/audio-decoder/ffmpeg "$APP/Contents/Helpers/ffmpeg"
codesign --force --sign - "$APP/Contents/Helpers/ffmpeg"
# Copy only supported models/resources. A previous build may leave retired
# model weights or dependency bundles in the shared build directory.
mkdir -p "$APP/Contents/Resources/Models"
for model in Who Voz Ear; do
    cp -R "$MODEL_DIR/$model" "$APP/Contents/Resources/Models/"
done
cp "$MODEL_DIR/MODELS.txt" "$APP/Contents/Resources/Models/"
for b in "$BIN_DIR"/DesertAnt_*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done
cp docs/THIRD_PARTY_NOTICES.txt "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Licenses"
cp .build/checkouts/desert-ant-core/LICENSE.md "$APP/Contents/Resources/Licenses/DesertAnt.md"
cp .build/audio-decoder/LICENSE.txt "$APP/Contents/Resources/Licenses/FFmpeg.txt"
cp .build/audio-decoder/BUILD.txt "$APP/Contents/Resources/Licenses/FFmpeg-build.txt"
cp Tools/build_audio_decoder.sh "$APP/Contents/Resources/Licenses/"
cp .build/audio-decoder/ffmpeg-source.tar.gz "$APP/Contents/Resources/Licenses/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Who Said What</string>
  <key>CFBundleDisplayName</key><string>Who Said What</string>
  <key>CFBundleIdentifier</key><string>com.andrisgauracs.whosaidwhat</string>
  <key>CFBundleExecutable</key><string>WhoSaidWhat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSpeechRecognitionUsageDescription</key><string>Transcribes recordings on this Mac. Missing Apple language assets may be downloaded from Apple.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
# Optional prefetch on the build/test Mac. Apple assets cannot be embedded.
if [[ -n "${WHO_SAID_WHAT_APPLE_LANGUAGES:-}" ]]; then
    "$APP/Contents/MacOS/WhoSaidWhat" --install-apple-assets "$WHO_SAID_WHAT_APPLE_LANGUAGES"
fi
# Preserve the last working app until all builds, model fetches and signing succeed.
rm -rf WhoSaidWhat.app
mv "$APP" WhoSaidWhat.app
print "Built $PWD/WhoSaidWhat.app"
du -sh WhoSaidWhat.app
