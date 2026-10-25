#!/bin/zsh
# Small LGPL FFmpeg build, limited to local audio decoding. No network protocols.
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/.build/ffmpeg-source"
OUTPUT="$PWD/.build/audio-decoder"
REVISION=239f2c733de417201d7ad3b3b8b0d9b63285b2b1
if [[ -x "$OUTPUT/ffmpeg" && -f "$OUTPUT/revision" && "$(cat "$OUTPUT/revision")" = "$REVISION" ]]; then
    exit 0
fi
if [[ ! -d "$SOURCE/.git" ]]; then
    git clone --depth 1 --branch n8.1.1 https://github.com/FFmpeg/FFmpeg.git "$SOURCE"
fi
[[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$REVISION" ]]
mkdir -p "$OUTPUT"
cd "$SOURCE"
./configure --prefix="$OUTPUT" --disable-everything --disable-autodetect \
    --disable-network --disable-doc --disable-debug --disable-shared --enable-static \
    --disable-programs --enable-ffmpeg --disable-swscale --disable-audiotoolbox \
    --disable-videotoolbox --disable-metal --disable-securetransport --disable-iconv \
    --enable-protocol=file --enable-demuxer=mov,matroska,aiff,caf,wav,mp3,flac,ogg,aac \
    --enable-decoder=aac,aac_fixed,mp3,mp3float,flac,vorbis,opus,alac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,pcm_f64le,pcm_s16be,pcm_s24be,pcm_s32be,pcm_f32be \
    --enable-parser=aac,aac_latm,mpegaudio,flac,opus,vorbis \
    --enable-encoder=pcm_f32le --enable-muxer=caf --enable-filter=aresample,aformat,anull \
    --extra-cflags=-mmacosx-version-min=26.0 --extra-ldflags=-mmacosx-version-min=26.0 \
    > "$OUTPUT/configure.log"
make -j 8 ffmpeg > "$OUTPUT/build.log" 2>&1
cp ffmpeg "$OUTPUT/ffmpeg"
strip "$OUTPUT/ffmpeg"
cp COPYING.LGPLv2.1 "$OUTPUT/LICENSE.txt"
git archive --format=tar.gz HEAD -o "$OUTPUT/ffmpeg-source.tar.gz"
printf '%s\n' "$REVISION" > "$OUTPUT/revision"
printf 'FFmpeg 8.1.1, source revision %s\nBuilt by Tools/build_audio_decoder.sh with local file protocol only.\nLGPL 2.1 or later; no GPL or nonfree components enabled.\n' "$REVISION" > "$OUTPUT/BUILD.txt"
