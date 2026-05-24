#!/bin/bash
#
# build-ffmpeg.sh - Configure and build custom FFmpeg with all features
#
# This script configures and compiles FFmpeg with:
# - Custom channel_layout_map option
# - All professional codecs (ProRes, DNxHD, H.264, HEVC, AV1, etc.)
# - Non-free AAC encoder (libfdk-aac)
# - GPU acceleration (NVENC, VAAPI)
# - Loudness metering
# - Subtitle rendering (libass)
# - Static binary output
#
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1}"
BUILD_DIR="${BUILD_DIR:-/opt/ffmpeg-build}"
PREFIX="${PREFIX:-/opt/ffmpeg}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
JOBS="${JOBS:-$(nproc)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo " Custom FFmpeg Build - v${FFMPEG_VERSION}"
echo "=========================================="
echo ""

# Download FFmpeg source
echo "=== Downloading FFmpeg ${FFMPEG_VERSION} source ==="
cd "${BUILD_DIR}"
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    if [ ! -f "ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
        wget -q "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    fi
    tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

FFMPEG_SRC="${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}"

# Apply our custom patches
echo "=== Applying custom patches ==="
bash "${SCRIPT_DIR}/apply-patches.sh" "${FFMPEG_SRC}"

# Configure FFmpeg
echo "=== Configuring FFmpeg ==="
cd "${FFMPEG_SRC}"

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"

./configure \
    --prefix="${PREFIX}" \
    --pkg-config-flags="--static" \
    --extra-cflags="-I${PREFIX}/include -static" \
    --extra-ldflags="-L${PREFIX}/lib -static" \
    --extra-libs="-lpthread -lm -lz -ldl" \
    --bindir="${OUTPUT_DIR}" \
    \
    --enable-gpl \
    --enable-nonfree \
    --enable-version3 \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-doc \
    \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libfdk-aac \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvpx \
    --enable-libaom \
    --enable-libsvtav1 \
    --enable-libass \
    \
    --enable-nvenc \
    --enable-vaapi \
    \
    --enable-openssl \
    \
    --enable-encoder=prores_ks \
    --enable-encoder=dnxhd \
    --enable-encoder=pcm_s16le \
    --enable-encoder=pcm_s24le \
    --enable-encoder=pcm_s32le \
    \
    --enable-decoder=prores \
    --enable-decoder=dnxhd \
    --enable-decoder=pcm_s16le \
    --enable-decoder=pcm_s24le \
    --enable-decoder=pcm_s32le \
    \
    --enable-muxer=mov \
    --enable-muxer=mp4 \
    --enable-muxer=mxf \
    --enable-muxer=matroska \
    --enable-muxer=wav \
    \
    --enable-demuxer=mov \
    --enable-demuxer=mxf \
    --enable-demuxer=matroska \
    --enable-demuxer=wav \
    \
    --enable-filter=channelmap \
    --enable-filter=pan \
    --enable-filter=loudnorm \
    --enable-filter=ebur128 \
    --enable-filter=scale \
    --enable-filter=fps \
    --enable-filter=setpts \
    --enable-filter=asetpts \
    --enable-filter=atempo \
    --enable-filter=adelay \
    --enable-filter=amix \
    --enable-filter=amerge \
    --enable-filter=asplit \
    --enable-filter=aresample \
    --enable-filter=volume \
    --enable-filter=dynaudnorm \
    --enable-filter=compand \
    --enable-filter=lut3d \
    --enable-filter=colorspace \
    --enable-filter=zscale \
    --enable-filter=overlay \
    --enable-filter=drawtext \
    --enable-filter=subtitles \
    --enable-filter=ass \
    --enable-filter=pad \
    --enable-filter=crop \
    --enable-filter=trim \
    --enable-filter=atrim \
    --enable-filter=select \
    --enable-filter=aselect \
    --enable-filter=split \
    --enable-filter=concat \
    --enable-filter=null \
    --enable-filter=anull \
    --enable-filter=format \
    --enable-filter=aformat

echo ""
echo "=== Building FFmpeg ==="
make -j${JOBS}

echo ""
echo "=== Installing FFmpeg ==="
mkdir -p "${OUTPUT_DIR}"
make install

# Verify the binary
echo ""
echo "=== Build Complete ==="
echo ""
"${OUTPUT_DIR}/ffmpeg" -version
echo ""
echo "Binary location: ${OUTPUT_DIR}/ffmpeg"
echo "Binary size: $(du -h "${OUTPUT_DIR}/ffmpeg" | cut -f1)"
echo ""

# Verify our custom option is recognized
echo "=== Verifying custom options ==="
if "${OUTPUT_DIR}/ffmpeg" -h full 2>&1 | grep -q "channel_layout_map"; then
    echo "✓ channel_layout_map option available"
else
    echo "⚠ channel_layout_map option not found in help (may still work via filter)"
fi

echo ""
echo "=== Available encoders ==="
"${OUTPUT_DIR}/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -E "(prores|dnxhd|264|265|aac|opus|av1|nvenc)" || true

echo ""
echo "Build complete! Binary ready at: ${OUTPUT_DIR}/ffmpeg"
