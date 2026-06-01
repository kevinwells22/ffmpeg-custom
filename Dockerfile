# ==============================================================================
# Custom FFmpeg Build - Multi-stage Dockerfile
#
# Produces a statically-linked FFmpeg binary with:
#   - ProRes, DNxHD/HR, H.264, HEVC, VP9, AV1, SVT-AV1
#   - Non-free AAC (libfdk-aac), MP3 (LAME), Opus
#   - GPU encoding (NVENC headers, VAAPI)
#   - Loudness metering (EBU R128, loudnorm)
#   - Subtitle rendering (libass)
#   - Professional broadcast features
#   - ProRes iTunes compliance (vendor=apl0, BT.709)
#   - MOV muxer: all audio/data tracks force-enabled
#   - asplit filter: unrestricted channel format passthrough
#
# Target: Debian 13 (trixie)
# Output: Standalone static binary at /output/ffmpeg
#
# Build:
#   docker build -t ffmpeg-custom-builder .
#   docker run --rm -v $(pwd)/output:/output ffmpeg-custom-builder
#
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build all dependencies and FFmpeg from source
# ------------------------------------------------------------------------------
FROM debian:trixie-slim AS builder

ARG FFMPEG_VERSION=7.1
ARG JOBS=0

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_DIR=/opt/ffmpeg-build
ENV PREFIX=/opt/ffmpeg
ENV OUTPUT_DIR=/output
ENV PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig"
ENV PATH="${PREFIX}/bin:${PATH}"

# Set JOBS to nproc if not specified (0 = auto)
SHELL ["/bin/bash", "-c"]

# Install base build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    libtool \
    meson \
    nasm \
    ninja-build \
    pkg-config \
    texinfo \
    wget \
    yasm \
    zlib1g-dev \
    python3 \
    libnuma-dev \
    linux-headers-amd64 \
    && rm -rf /var/lib/apt/lists/*

# Create build directories
RUN mkdir -p ${BUILD_DIR} ${PREFIX} ${OUTPUT_DIR}

# Set JOBS
RUN if [ "${JOBS}" = "0" ]; then echo "export JOBS=$(nproc)" >> /etc/profile.d/jobs.sh; \
    else echo "export JOBS=${JOBS}" >> /etc/profile.d/jobs.sh; fi
RUN source /etc/profile.d/jobs.sh || true

# --- Build OpenSSL (static) ---
RUN cd ${BUILD_DIR} && \
    wget -q https://github.com/openssl/openssl/releases/download/openssl-3.3.1/openssl-3.3.1.tar.gz && \
    tar xzf openssl-3.3.1.tar.gz && \
    cd openssl-3.3.1 && \
    ./Configure --prefix=${PREFIX} --openssldir=${PREFIX}/ssl --libdir=lib \
        no-shared no-tests linux-x86_64 && \
    make -j$(nproc) && make install_sw

# --- Build x264 ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://code.videolan.org/videolan/x264.git && \
    cd x264 && \
    ./configure --prefix=${PREFIX} --enable-static --enable-pic --disable-cli && \
    make -j$(nproc) && make install

# --- Build x265 (pinned to version compatible with FFmpeg 7.1) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 --branch 4.0 https://bitbucket.org/multicoreware/x265_git.git && \
    cd x265_git/build/linux && \
    cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX=${PREFIX} \
        -DLIB_INSTALL_DIR=${PREFIX}/lib \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
        -DSTATIC_LINK_CRT=ON \
        -DENABLE_LIBNUMA=ON \
        ../../source && \
    make -j$(nproc) && make install && \
    mkdir -p ${PREFIX}/lib/pkgconfig && \
    echo "prefix=${PREFIX}" > ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "exec_prefix=\${prefix}" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "libdir=\${prefix}/lib" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "includedir=\${prefix}/include" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "Name: x265" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "Description: H.265/HEVC video encoder" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "Version: $(cat ../../source/x265Version.txt 2>/dev/null | head -1 || echo '3.6')" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "Libs: -L\${libdir} -lx265 -lstdc++ -lm -lnuma -ldl -lpthread" >> ${PREFIX}/lib/pkgconfig/x265.pc && \
    echo "Cflags: -I\${includedir}" >> ${PREFIX}/lib/pkgconfig/x265.pc

# --- Build libfdk-aac (non-free) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://github.com/mstorsjo/fdk-aac.git && \
    cd fdk-aac && \
    autoreconf -fiv && \
    ./configure --prefix=${PREFIX} --enable-static --disable-shared && \
    make -j$(nproc) && make install

# --- Build libmp3lame ---
RUN cd ${BUILD_DIR} && \
    wget -q "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" && \
    tar xzf lame-3.100.tar.gz && \
    cd lame-3.100 && \
    ./configure --prefix=${PREFIX} --enable-static --disable-shared --enable-nasm && \
    make -j$(nproc) && make install

# --- Build libopus ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://github.com/xiph/opus.git && \
    cd opus && \
    autoreconf -fiv && \
    ./configure --prefix=${PREFIX} --enable-static --disable-shared && \
    make -j$(nproc) && make install

# --- Build libvpx ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git && \
    cd libvpx && \
    ./configure --prefix=${PREFIX} \
        --enable-static --disable-shared \
        --disable-examples --disable-tools \
        --disable-unit-tests --enable-vp9-highbitdepth \
        --enable-pic && \
    make -j$(nproc) && make install

# --- Build libaom (AV1) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://aomedia.googlesource.com/aom && \
    mkdir -p aom/build && cd aom/build && \
    cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX=${PREFIX} \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_TESTS=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_TOOLS=OFF \
        -DENABLE_NASM=ON \
        .. && \
    make -j$(nproc) && make install

# --- Build SVT-AV1 (pinned to version compatible with FFmpeg 7.1) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 --branch v2.3.0 https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
    mkdir -p SVT-AV1/build && cd SVT-AV1/build && \
    cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX=${PREFIX} \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_APPS=OFF \
        -DBUILD_DEC=ON \
        .. && \
    make -j$(nproc) && make install

# --- Build freetype (for harfbuzz, then rebuild with harfbuzz) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://gitlab.freedesktop.org/freetype/freetype.git && \
    cd freetype && \
    ./autogen.sh && \
    ./configure --prefix=${PREFIX} --enable-static --disable-shared --with-harfbuzz=no && \
    make -j$(nproc) && make install

# --- Build harfbuzz (for libass) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://github.com/harfbuzz/harfbuzz.git && \
    cd harfbuzz && \
    PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig" \
    meson setup build --prefix=${PREFIX} --default-library=static \
        -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled \
        -Dcairo=disabled -Dicu=disabled -Dtests=disabled \
        -Ddocs=disabled -Dintrospection=disabled && \
    ninja -C build && ninja -C build install

# --- Rebuild freetype with harfbuzz support ---
RUN cd ${BUILD_DIR}/freetype && \
    make clean && \
    PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig" \
    ./configure --prefix=${PREFIX} --enable-static --disable-shared --with-harfbuzz=yes && \
    make -j$(nproc) && make install

# --- Build fribidi (for libass) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://github.com/fribidi/fribidi.git && \
    cd fribidi && \
    meson setup build --prefix=${PREFIX} --default-library=static -Ddocs=false && \
    ninja -C build && ninja -C build install

# --- Build libass (without system font provider - embedded fonts still work) ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://github.com/libass/libass.git && \
    cd libass && \
    autoreconf -fiv && \
    PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig" \
    ./configure --prefix=${PREFIX} --enable-static --disable-shared \
        --disable-require-system-font-provider && \
    make -j$(nproc) && make install

# --- Install NVIDIA codec headers ---
RUN cd ${BUILD_DIR} && \
    git clone --depth 1 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make PREFIX=${PREFIX} install

# --- Copy custom source files ---
COPY src/ /custom-src/
COPY scripts/ /custom-scripts/

# --- Download and build FFmpeg ---
RUN cd ${BUILD_DIR} && \
    wget -q "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" && \
    tar xf ffmpeg-${FFMPEG_VERSION}.tar.xz

# Apply custom patches
RUN bash /custom-scripts/apply-patches.sh ${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION} /custom-src

# Configure and build FFmpeg
RUN cd ${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION} && \
    PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig" \
    ./configure \
        --prefix=${PREFIX} \
        --pkg-config-flags="--static" \
        --extra-cflags="-I${PREFIX}/include" \
        --extra-ldflags="-static -L${PREFIX}/lib -L${PREFIX}/lib/x86_64-linux-gnu" \
        --extra-libs="-lpthread -lm -lz -ldl -lstdc++ -lnuma" \
        --bindir=${OUTPUT_DIR} \
        \
        --enable-gpl \
        --enable-nonfree \
        --enable-version3 \
        --enable-static \
        --disable-shared \
        --disable-debug \
        --disable-doc \
        --disable-ffplay \
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
        --enable-openssl \
        --enable-nvenc && \
    make -j$(nproc) && \
    make install

# Verify build
RUN ${OUTPUT_DIR}/ffmpeg -version && \
    ${OUTPUT_DIR}/ffprobe -version && \
    echo "Build successful!"

# ------------------------------------------------------------------------------
# Stage 2: Minimal output image with just the binaries
# ------------------------------------------------------------------------------
FROM debian:trixie-slim AS output

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /output/ffmpeg /usr/local/bin/ffmpeg
COPY --from=builder /output/ffprobe /usr/local/bin/ffprobe

# Verify binaries work
RUN /usr/local/bin/ffmpeg -version && /usr/local/bin/ffprobe -version

ENTRYPOINT ["ffmpeg"]
CMD ["-version"]

# ------------------------------------------------------------------------------
# Stage 3: Export target (extract binary only)
# Use: docker build --target=export --output=./output .
# ------------------------------------------------------------------------------
FROM scratch AS export
COPY --from=builder /output/ffmpeg /ffmpeg
COPY --from=builder /output/ffprobe /ffprobe
