#!/bin/bash
#
# iTunes-Compliant ProRes Transcoding Examples
#
# These examples use the custom FFmpeg build with:
#   - channel_layout_map support
#   - Auto BT.709 color tagging for ProRes
#   - Force-enabled audio tracks
#   - Apple vendor ID default (apl0)
#
# ============================================================================

FFMPEG="${FFMPEG:-ffmpeg}"

# ============================================================================
# Example 1: HD ProRes 422 HQ with 5.1+Stereo audio (your original workflow)
# ============================================================================
#
# Reorders channels from source layout to: L,R,C,LFE,LS,RS,Lt,Rt
# Uses channel_layout_map for reorder + labeling in one step
#
example_hd_prores_surround() {
    local INPUT="$1"
    local OUTPUT="$2"

    ${FFMPEG} -hide_banner -y \
        -progress pipe:1 -nostats \
        -i "${INPUT}" \
        -c:v prores_ks \
        -profile:v 3 \
        -pix_fmt yuv422p10le \
        -sws_flags lanczos \
        -vf "scale=1920:1080" \
        -color_primaries bt709 \
        -color_trc bt709 \
        -colorspace bt709 \
        -timecode 00:00:00:00 \
        -c:a pcm_s24le \
        -ar 48000 \
        -channel_layout_map "2,3,4,5,6,7,0-1:L,R,C,LFE,LS,RS,LT-RT" \
        -vtag apch \
        -vendor apl0 \
        -flags +bitexact \
        -movflags +write_colr \
        -f mov \
        -shortest \
        "${OUTPUT}"
}

# ============================================================================
# Example 2: HD ProRes 422 HQ - Stereo only (iTunes simplest delivery)
# ============================================================================
example_hd_prores_stereo() {
    local INPUT="$1"
    local OUTPUT="$2"

    ${FFMPEG} -hide_banner -y \
        -progress pipe:1 -nostats \
        -i "${INPUT}" \
        -c:v prores_ks \
        -profile:v 3 \
        -pix_fmt yuv422p10le \
        -sws_flags lanczos \
        -vf "scale=1920:1080" \
        -color_primaries bt709 \
        -color_trc bt709 \
        -colorspace bt709 \
        -timecode 00:00:00:00 \
        -c:a pcm_s24le \
        -ar 48000 \
        -ac 2 \
        -vtag apch \
        -vendor apl0 \
        -flags +bitexact \
        -movflags +write_colr \
        -f mov \
        "${OUTPUT}"
}

# ============================================================================
# Example 3: 4K UHD ProRes 422 HQ (iTunes 4K delivery)
# ============================================================================
example_4k_prores() {
    local INPUT="$1"
    local OUTPUT="$2"

    ${FFMPEG} -hide_banner -y \
        -progress pipe:1 -nostats \
        -i "${INPUT}" \
        -c:v prores_ks \
        -profile:v 3 \
        -pix_fmt yuv422p10le \
        -sws_flags lanczos \
        -vf "scale=3840:2160" \
        -color_primaries bt709 \
        -color_trc bt709 \
        -colorspace bt709 \
        -timecode 00:00:00:00 \
        -c:a pcm_s24le \
        -ar 48000 \
        -vtag apch \
        -vendor apl0 \
        -flags +bitexact \
        -movflags +write_colr \
        -f mov \
        "${OUTPUT}"
}

# ============================================================================
# Example 4: ProRes 4444 with HDR (PQ/BT.2020 for Dolby Vision base layer)
# ============================================================================
example_hdr_prores4444() {
    local INPUT="$1"
    local OUTPUT="$2"

    ${FFMPEG} -hide_banner -y \
        -progress pipe:1 -nostats \
        -i "${INPUT}" \
        -c:v prores_ks \
        -profile:v 4 \
        -pix_fmt yuva444p10le \
        -sws_flags lanczos \
        -vf "scale=3840:2160" \
        -color_primaries bt2020 \
        -color_trc smpte2084 \
        -colorspace bt2020nc \
        -timecode 00:00:00:00 \
        -c:a pcm_s24le \
        -ar 48000 \
        -vtag ap4h \
        -vendor apl0 \
        -flags +bitexact \
        -movflags +write_colr \
        -f mov \
        "${OUTPUT}"
}

# ============================================================================
# Example 5: Multi-track audio with separate channel groups
#             (8 tracks: 5.1 mix + stereo Lt/Rt)
# ============================================================================
#
# Uses asplit + channelmap for complex multi-track delivery
# Each audio group gets its own properly-labeled track
#
example_multitrack_delivery() {
    local INPUT="$1"
    local OUTPUT="$2"

    ${FFMPEG} -hide_banner -y \
        -progress pipe:1 -nostats \
        -i "${INPUT}" \
        -c:v prores_ks \
        -profile:v 3 \
        -pix_fmt yuv422p10le \
        -sws_flags lanczos \
        -vf "scale=1920:1080" \
        -color_primaries bt709 \
        -color_trc bt709 \
        -colorspace bt709 \
        -timecode 00:00:00:00 \
        -map 0:v:0 \
        -map 0:a:0 \
        -map 0:a:0 \
        -c:a pcm_s24le \
        -ar 48000 \
        -filter:a:0 "channelmap=map=0-FL|1-FR|2-FC|3-LFE|4-SL|5-SR:channel_layout=5.1" \
        -filter:a:1 "channelmap=map=6-DL|7-DR:channel_layout=downmix" \
        -vtag apch \
        -vendor apl0 \
        -flags +bitexact \
        -movflags +write_colr \
        -f mov \
        "${OUTPUT}"
}

# ============================================================================
# Example 6: Loudness-normalized ProRes (EBU R128 → -24 LUFS for iTunes)
# ============================================================================
#
# iTunes requires dialogue-normalized audio around -24 LUFS (±2).
# This uses the loudnorm filter for two-pass loudness correction.
#
example_loudnorm_prores() {
    local INPUT="$1"
    local OUTPUT="$2"

    # Pass 1: Measure loudness
    echo "=== Pass 1: Measuring loudness ==="
    LOUDNESS=$(${FFMPEG} -hide_banner -i "${INPUT}" \
        -af "loudnorm=I=-24:TP=-2:LRA=7:print_format=json" \
        -f null /dev/null 2>&1 | \
        grep -A20 '"input_' | head -20)

    INPUT_I=$(echo "$LOUDNESS" | grep "input_i" | grep -oP '[-\d.]+')
    INPUT_TP=$(echo "$LOUDNESS" | grep "input_tp" | grep -oP '[-\d.]+')
    INPUT_LRA=$(echo "$LOUDNESS" | grep "input_lra" | grep -oP '[-\d.]+')
    INPUT_THRESH=$(echo "$LOUDNESS" | grep "input_thresh" | grep -oP '[-\d.]+')

    echo "  Measured: I=${INPUT_I}, TP=${INPUT_TP}, LRA=${INPUT_LRA}"

    # Pass 2: Apply correction
    echo "=== Pass 2: Encoding with loudness normalization ==="
    ${FFMPEG} -hide_banner -y \
        -progress pipe:1 -nostats \
        -i "${INPUT}" \
        -c:v prores_ks \
        -profile:v 3 \
        -pix_fmt yuv422p10le \
        -color_primaries bt709 \
        -color_trc bt709 \
        -colorspace bt709 \
        -af "loudnorm=I=-24:TP=-2:LRA=7:measured_I=${INPUT_I}:measured_TP=${INPUT_TP}:measured_LRA=${INPUT_LRA}:measured_thresh=${INPUT_THRESH}:linear=true" \
        -c:a pcm_s24le \
        -ar 48000 \
        -vtag apch \
        -vendor apl0 \
        -flags +bitexact \
        -movflags +write_colr \
        -f mov \
        "${OUTPUT}"
}

# ============================================================================
# Usage
# ============================================================================
echo "iTunes-Compliant ProRes Transcoding Examples"
echo ""
echo "Functions available:"
echo "  example_hd_prores_surround  <input> <output>  - HD 422HQ + 5.1/Lt-Rt"
echo "  example_hd_prores_stereo    <input> <output>  - HD 422HQ + Stereo"
echo "  example_4k_prores           <input> <output>  - 4K UHD 422HQ"
echo "  example_hdr_prores4444      <input> <output>  - 4K HDR ProRes 4444"
echo "  example_multitrack_delivery <input> <output>  - Multi-track audio"
echo "  example_loudnorm_prores     <input> <output>  - Loudness-normalized"
echo ""
echo "Source this file and call functions:"
echo "  source examples/itunes-prores-delivery.sh"
echo "  example_hd_prores_surround input.mxf output.mov"
