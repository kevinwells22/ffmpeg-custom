#!/bin/bash
#
# apply-patches.sh - Apply custom source overlays to FFmpeg source tree
#
# This script copies our custom source files into the FFmpeg source tree
# and patches the build system to include them.
#
# Patches applied:
#   1. ProRes iTunes compliance (auto BT.709 color, vendor=apl0)
#   2. asplit filter: unrestricted channel format passthrough
#   3. MOV muxer: all audio/data tracks force-enabled (flags=0xF)
#   4. ProRes encoder: default vendor = apl0 (Apple)
#   5. channel_layout_map CLI option (channel reorder + relabel)
#
set -euo pipefail

FFMPEG_SRC="${1:?Usage: apply-patches.sh <ffmpeg-source-dir> [patch-source-dir]}"
PATCH_SRC="${2:-$(cd "$(dirname "$0")/.." && pwd)/src}"

# Fallback: check common Docker locations
if [ ! -d "${PATCH_SRC}" ]; then
    if [ -d "/custom-src" ]; then
        PATCH_SRC="/custom-src"
    elif [ -d "$(dirname "$0")/../src" ]; then
        PATCH_SRC="$(cd "$(dirname "$0")/../src" && pwd)"
    fi
fi

echo "=== Applying custom patches to FFmpeg source: ${FFMPEG_SRC} ==="

# 1. Copy ProRes iTunes compliance module
echo "[1/4] Adding ProRes iTunes compliance auto-defaults..."
cp "${PATCH_SRC}/fftools/ffmpeg_prores_compliance.c" "${FFMPEG_SRC}/fftools/"
cp "${PATCH_SRC}/fftools/ffmpeg_prores_compliance.h" "${FFMPEG_SRC}/fftools/"

# Add to fftools Makefile
if ! grep -q "ffmpeg_prores_compliance" "${FFMPEG_SRC}/fftools/Makefile"; then
    sed -i '/^OBJS-ffmpeg.*ffmpeg_opt/a OBJS-ffmpeg += fftools/ffmpeg_prores_compliance.o' \
        "${FFMPEG_SRC}/fftools/Makefile"
    echo "  -> Added ffmpeg_prores_compliance.o to build"
fi

# Hook into ffmpeg_enc.c to call our defaults
ENCFILE="${FFMPEG_SRC}/fftools/ffmpeg_enc.c"
if [ -f "${ENCFILE}" ] && ! grep -q "prores_compliance" "${ENCFILE}"; then
    sed -i '/#include.*ffmpeg.h/a #include "fftools/ffmpeg_prores_compliance.h"' \
        "${ENCFILE}" 2>/dev/null || true
    # Insert call after encoder is opened
    sed -i '/avcodec_open2.*== 0\|ret = avcodec_open2/{
        n
        /^$/a\    ff_prores_itunes_apply_defaults(enc_ctx, oc->oformat->name);
    }' "${ENCFILE}" 2>/dev/null || true
    echo "  -> Hooked ProRes compliance into encoder init"
fi

# 2. Patch asplit filter to accept all channel formats/counts
echo "[2/4] Patching libavfilter/split.c for unrestricted channel format support..."

SPLITFILE="${FFMPEG_SRC}/libavfilter/split.c"
if [ -f "${SPLITFILE}" ] && ! grep -q "query_formats.*all" "${SPLITFILE}"; then
    # Add formats.h include if not present
    if ! grep -q '#include "formats.h"' "${SPLITFILE}"; then
        sed -i '/#include "audio.h"/a #include "formats.h"' "${SPLITFILE}"
    fi

    # Add .query_formats to asplit filter definition
    if grep -q "ff_af_asplit" "${SPLITFILE}"; then
        sed -i '/ff_af_asplit/,/};/ {
            /\.inputs/i\    .query_formats = ff_query_formats_all,
        }' "${SPLITFILE}" 2>/dev/null || true
    elif grep -q "asplit_outputs\|AVFILTER_FLAG_DYNAMIC_OUTPUTS" "${SPLITFILE}"; then
        sed -i '/AVFILTER_FLAG_DYNAMIC_OUTPUTS/{
            /asplit/!b
            a\    .formats.query_func = ff_query_formats_all,
        }' "${SPLITFILE}" 2>/dev/null || true
    fi
    echo "  -> Patched split.c (asplit accepts all channel formats)"
else
    echo "  -> split.c already patched or not found (skipping)"
fi

# 3. Patch MOV muxer to force-enable all audio/data tracks
echo "[3/4] Patching libavformat/movenc.c for force-enabled tracks..."

MOVENC="${FFMPEG_SRC}/libavformat/movenc.c"
if [ -f "${MOVENC}" ] && ! grep -q "enable all audio & data tracks" "${MOVENC}"; then
    # Force flags=0xF for audio and data tracks in tkhd
    sed -i '/avio_w8(pb, version);/{
        n
        /avio_wb24(pb, flags);/{
            i\    if (track->par->codec_type == AVMEDIA_TYPE_AUDIO ||\
        track->par->codec_type == AVMEDIA_TYPE_DATA) /* enable all audio \& data tracks */\
        avio_wb24(pb, 0xf);\
    else
        }
    }' "${MOVENC}" 2>/dev/null || true

    # Set alternate group to 0 so all tracks are independent
    sed -i 's/avio_wb16(pb, group); \/\* alternate group/avio_wb16(pb, 0x0); \/* alternate group=0 (all tracks independent)/' \
        "${MOVENC}" 2>/dev/null || true

    echo "  -> Patched movenc.c (all audio/data tracks force-enabled, alt_group=0)"
else
    echo "  -> movenc.c already patched or not found (skipping)"
fi

# 4. Patch ProRes encoder to default vendor=apl0 for MOV output
echo "[4/4] Patching prores_ks encoder for Apple vendor default..."

PRORES_KS="${FFMPEG_SRC}/libavcodec/proresenc_kostya.c"
if [ -f "${PRORES_KS}" ] && ! grep -q "apl0.*default" "${PRORES_KS}"; then
    # Change default vendor from "fmpg" to "apl0" for Apple compatibility
    sed -i 's/"fmpg"/"apl0"/g' "${PRORES_KS}" 2>/dev/null || true
    echo "  -> Default vendor changed to 'apl0' (Apple)"
else
    echo "  -> proresenc_kostya.c already patched or not found (skipping)"
fi

echo ""
echo "[5/5] Applying channel_layout_map option patch..."
CLM_PATCH="$(cd "$(dirname "$0")/.." && pwd)/patches/0004-add-channel-layout-map-option.patch"
if [ ! -f "${CLM_PATCH}" ] && [ -f "/custom-patches/0004-add-channel-layout-map-option.patch" ]; then
    CLM_PATCH="/custom-patches/0004-add-channel-layout-map-option.patch"
fi

if [ -f "${CLM_PATCH}" ]; then
    if ! grep -q "channel_layout_map" "${FFMPEG_SRC}/fftools/ffmpeg_opt.c"; then
        patch -d "${FFMPEG_SRC}" -p1 < "${CLM_PATCH}"
        echo "  -> Applied channel_layout_map patch"
    else
        echo "  -> channel_layout_map already present (skipping)"
    fi
else
    echo "  -> channel_layout_map patch file not found (skipping)"
fi

echo ""
echo "=== Patches applied successfully ==="
echo "Custom features added:"
echo "  - ProRes iTunes compliance (auto BT.709 color, vendor=apl0)"
echo "  - asplit filter: unrestricted channel format passthrough"
echo "  - MOV muxer: all audio/data tracks force-enabled (flags=0xF)"
echo "  - MOV muxer: alternate group set to 0 (no hidden tracks)"
echo "  - channel_layout_map option for channel reorder + relabel"
echo ""
