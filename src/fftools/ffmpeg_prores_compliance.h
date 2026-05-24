/*
 * ProRes iTunes Compliance header
 * Copyright (c) 2025 Custom Build
 * License: LGPL 2.1+
 */

#ifndef FFMPEG_PRORES_COMPLIANCE_H
#define FFMPEG_PRORES_COMPLIANCE_H

#include "libavcodec/avcodec.h"

/**
 * Apply iTunes-compliant defaults to a ProRes encoder context.
 *
 * Automatically sets BT.709 color metadata when encoding ProRes to MOV
 * if not explicitly specified by the user. This prevents the most common
 * iTunes compliance failure (missing/unspecified color tags).
 *
 * Safe to call for any codec/format - returns immediately if not ProRes+MOV.
 *
 * @param enc  The encoder context
 * @param fmt  Output format name ("mov", etc.)
 * @return 0 on success
 */
int ff_prores_itunes_apply_defaults(AVCodecContext *enc, const char *fmt);

#endif /* FFMPEG_PRORES_COMPLIANCE_H */
