#!/bin/bash
#
# verify-itunes-compliance.sh - Check a ProRes MOV file for iTunes compliance
#
# Uses ffprobe to validate the key requirements Apple checks.
# Run: ./verify-itunes-compliance.sh output.mov
#
set -euo pipefail

FFPROBE="${FFPROBE:-ffprobe}"
FILE="${1:?Usage: verify-itunes-compliance.sh <file.mov>}"

echo "=============================================="
echo " iTunes ProRes Compliance Check"
echo " File: ${FILE}"
echo "=============================================="
echo ""

PASS=0
FAIL=0
WARN=0

check_pass() { echo "  ✓ PASS: $1"; ((PASS++)); }
check_fail() { echo "  ✗ FAIL: $1"; ((FAIL++)); }
check_warn() { echo "  ⚠ WARN: $1"; ((WARN++)); }

# Get stream info as JSON
INFO=$(${FFPROBE} -v quiet -print_format json -show_format -show_streams "${FILE}")

# --- Container check ---
echo "[Container]"
FORMAT=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['format']['format_name'])" 2>/dev/null)
if echo "$FORMAT" | grep -q "mov"; then
    check_pass "Container is QuickTime MOV"
else
    check_fail "Container is '${FORMAT}', expected MOV"
fi

# --- Video codec check ---
echo ""
echo "[Video]"
VCODEC=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(s.get('codec_name','unknown'))
        break
" 2>/dev/null)

if echo "$VCODEC" | grep -q "prores"; then
    check_pass "Video codec: ProRes (${VCODEC})"
else
    check_fail "Video codec: ${VCODEC} (expected prores)"
fi

# Profile check
VPROFILE=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(s.get('profile','unknown'))
        break
" 2>/dev/null)
echo "  → Profile: ${VPROFILE}"

# Resolution
RESOLUTION=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(f\"{s['width']}x{s['height']}\")
        break
" 2>/dev/null)
echo "  → Resolution: ${RESOLUTION}"

# Pixel format
PIXFMT=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(s.get('pix_fmt','unknown'))
        break
" 2>/dev/null)
if echo "$PIXFMT" | grep -q "yuv422p10\|yuva444p10"; then
    check_pass "Pixel format: ${PIXFMT} (10-bit)"
else
    check_warn "Pixel format: ${PIXFMT} (expected 10-bit 422 or 444)"
fi

# Color metadata
COLOR_PRI=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(s.get('color_primaries','unspecified'))
        break
" 2>/dev/null)
COLOR_TRC=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(s.get('color_transfer','unspecified'))
        break
" 2>/dev/null)
COLOR_SPC=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='video':
        print(s.get('color_space','unspecified'))
        break
" 2>/dev/null)

echo ""
echo "[Color Metadata]"
if [ "$COLOR_PRI" = "bt709" ]; then
    check_pass "Color primaries: ${COLOR_PRI}"
else
    check_fail "Color primaries: '${COLOR_PRI}' (expected bt709 for SDR)"
fi

if [ "$COLOR_TRC" = "bt709" ]; then
    check_pass "Color transfer: ${COLOR_TRC}"
else
    check_fail "Color transfer: '${COLOR_TRC}' (expected bt709 for SDR)"
fi

if [ "$COLOR_SPC" = "bt709" ]; then
    check_pass "Color space: ${COLOR_SPC}"
else
    check_fail "Color space: '${COLOR_SPC}' (expected bt709 for SDR)"
fi

# --- Audio check ---
echo ""
echo "[Audio]"
ACODEC=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='audio':
        print(s.get('codec_name','unknown'))
        break
" 2>/dev/null)

if echo "$ACODEC" | grep -q "pcm_s16\|pcm_s24\|pcm_s32"; then
    check_pass "Audio codec: ${ACODEC} (LPCM)"
else
    check_warn "Audio codec: ${ACODEC} (iTunes prefers LPCM for ProRes delivery)"
fi

ARATE=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='audio':
        print(s.get('sample_rate','0'))
        break
" 2>/dev/null)

if [ "$ARATE" -ge 48000 ] 2>/dev/null; then
    check_pass "Sample rate: ${ARATE} Hz (≥48kHz)"
else
    check_fail "Sample rate: ${ARATE} Hz (must be ≥48kHz)"
fi

# Channel count
ACHANNELS=$(echo "$INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['streams']:
    if s['codec_type']=='audio':
        print(s.get('channels','0'))
        break
" 2>/dev/null)
echo "  → Channels: ${ACHANNELS}"

# --- Vendor tag check (via atoms) ---
echo ""
echo "[Vendor/Tags]"
VTAG=$(${FFPROBE} -v quiet -show_entries stream_tags=encoder -of default=nw=1:nk=1 "${FILE}" 2>/dev/null | head -1)
echo "  → Encoder tag: ${VTAG:-not set}"

# --- Summary ---
echo ""
echo "=============================================="
echo " Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
echo "=============================================="

if [ $FAIL -eq 0 ]; then
    echo " STATUS: LIKELY COMPLIANT"
    echo ""
    echo " Note: This checks metadata only. Apple's final"
    echo " validation also checks frame structure, edit lists,"
    echo " and requires black frames at start/end."
else
    echo " STATUS: NOT COMPLIANT - fix failures above"
fi

exit $FAIL
