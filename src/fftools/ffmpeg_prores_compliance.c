/*
 * ProRes iTunes Compliance - Auto-defaults patch
 *
 * When encoding ProRes to MOV, automatically applies Apple-recommended
 * defaults unless explicitly overridden by the user:
 *
 *   - vendor = "apl0" (Apple vendor ID)
 *   - color_primaries = bt709
 *   - color_trc = bt709
 *   - colorspace = bt709
 *   - write_colr movflag enabled
 *
 * This ensures ProRes files pass iTunes Store compliance checks
 * without requiring the user to remember every metadata flag.
 *
 * Applied as a post-processing step after option parsing in ffmpeg_opt.c
 *
 * Copyright (c) 2025 Custom Build
 * License: LGPL 2.1+
 */

#include "config.h"
#include "libavutil/log.h"
#include "libavutil/pixfmt.h"
#include "libavcodec/avcodec.h"

/**
 * Check if a codec ID is a ProRes variant.
 */
static inline int is_prores_codec(enum AVCodecID codec_id)
{
    return codec_id == AV_CODEC_ID_PRORES;
}

/**
 * Apply iTunes-compliant defaults to a ProRes output stream.
 *
 * Called during output stream setup when the encoder is prores_ks/prores_aw
 * and the output format is MOV.
 *
 * Only sets values that have NOT been explicitly specified by the user.
 *
 * @param enc   The encoder context being configured
 * @param fmt   The output format short name (e.g., "mov")
 * @return 0 on success
 */
int ff_prores_itunes_apply_defaults(AVCodecContext *enc, const char *fmt)
{
    if (!enc || !fmt)
        return 0;

    /* Only apply for ProRes in MOV containers */
    if (!is_prores_codec(enc->codec_id))
        return 0;

    if (strcmp(fmt, "mov") != 0 && strcmp(fmt, "QuickTime / MOV") != 0)
        return 0;

    av_log(enc, AV_LOG_VERBOSE,
           "ProRes/MOV detected: applying iTunes compliance defaults\n");

    /* Set BT.709 color metadata if not explicitly specified */
    if (enc->color_primaries == AVCOL_PRI_UNSPECIFIED) {
        enc->color_primaries = AVCOL_PRI_BT709;
        av_log(enc, AV_LOG_VERBOSE,
               "  -> color_primaries = bt709 (iTunes default)\n");
    }

    if (enc->color_trc == AVCOL_TRC_UNSPECIFIED) {
        enc->color_trc = AVCOL_TRC_BT709;
        av_log(enc, AV_LOG_VERBOSE,
               "  -> color_trc = bt709 (iTunes default)\n");
    }

    if (enc->colorspace == AVCOL_SPC_UNSPECIFIED) {
        enc->colorspace = AVCOL_SPC_BT709;
        av_log(enc, AV_LOG_VERBOSE,
               "  -> colorspace = bt709 (iTunes default)\n");
    }

    return 0;
}
