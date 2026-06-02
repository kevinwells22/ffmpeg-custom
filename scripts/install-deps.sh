#!/bin/bash
#
# install-deps.sh - Install all build dependencies for custom FFmpeg
#
# Target: Debian 13 (trixie)
# Builds all codec libraries from source for static linking
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
BUILD_DIR="${BUILD_DIR:-/opt/ffmpeg-build}"
PREFIX="${PREFIX:-/opt/ffmpeg}"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "${BUILD_DIR}" "${PREFIX}"

echo "=== Installing base build dependencies ==="
apt-get update && apt-get install -y --no-install-recommends \
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
    libssl-dev \
    python3 \
    python3-pip

echo "=== Building static libraries ==="

# --- x264 (H.264 encoder) ---
echo "[1/13] Building x264..."
cd "${BUILD_DIR}"
if [ ! -d x264 ]; then
    git clone --depth 1 https://code.videolan.org/videolan/x264.git
fi
cd x264
./configure --prefix="${PREFIX}" --enable-static --enable-pic --disable-cli
make -j${JOBS} && make install

# --- x265 (HEVC encoder) ---
echo "[2/13] Building x265..."
cd "${BUILD_DIR}"
if [ ! -d x265_git ]; then
    git clone --depth 1 https://bitbucket.org/multicoreware/x265_git.git
fi
cd x265_git/build/linux
cmake -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DSTATIC_LINK_CRT=ON \
    ../../source
make -j${JOBS} && make install

# --- libfdk-aac (AAC encoder - non-free) ---
echo "[3/13] Building libfdk-aac..."
cd "${BUILD_DIR}"
if [ ! -d fdk-aac ]; then
    git clone --depth 1 https://github.com/mstorsjo/fdk-aac.git
fi
cd fdk-aac
autoreconf -fiv
./configure --prefix="${PREFIX}" --enable-static --disable-shared
make -j${JOBS} && make install

# --- libmp3lame (MP3 encoder) ---
echo "[4/13] Building libmp3lame..."
cd "${BUILD_DIR}"
LAME_VER="3.100"
if [ ! -d "lame-${LAME_VER}" ]; then
    wget -q "https://downloads.sourceforge.net/project/lame/lame/${LAME_VER}/lame-${LAME_VER}.tar.gz"
    tar xzf "lame-${LAME_VER}.tar.gz"
fi
cd "lame-${LAME_VER}"
./configure --prefix="${PREFIX}" --enable-static --disable-shared --enable-nasm
make -j${JOBS} && make install

# --- libopus (Opus audio codec) ---
echo "[5/13] Building libopus..."
cd "${BUILD_DIR}"
if [ ! -d opus ]; then
    git clone --depth 1 https://github.com/xiph/opus.git
fi
cd opus
autoreconf -fiv
./configure --prefix="${PREFIX}" --enable-static --disable-shared
make -j${JOBS} && make install

# --- libvpx (VP8/VP9) ---
echo "[6/13] Building libvpx..."
cd "${BUILD_DIR}"
if [ ! -d libvpx ]; then
    git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git
fi
cd libvpx
./configure --prefix="${PREFIX}" \
    --enable-static --disable-shared \
    --disable-examples --disable-tools \
    --disable-unit-tests --enable-vp9-highbitdepth \
    --enable-pic
make -j${JOBS} && make install

# --- libaom (AV1) ---
echo "[7/13] Building libaom..."
cd "${BUILD_DIR}"
if [ ! -d aom ]; then
    git clone --depth 1 https://aomedia.googlesource.com/aom
fi
mkdir -p aom/build && cd aom/build
cmake -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_TOOLS=OFF \
    -DENABLE_NASM=ON \
    ..
make -j${JOBS} && make install

# --- SVT-AV1 (faster AV1 encoder) ---
echo "[8/13] Building SVT-AV1..."
cd "${BUILD_DIR}"
if [ ! -d SVT-AV1 ]; then
    git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
fi
mkdir -p SVT-AV1/build && cd SVT-AV1/build
cmake -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_APPS=OFF \
    -DBUILD_DEC=ON \
    ..
make -j${JOBS} && make install

# --- libass (subtitle rendering) ---
echo "[9/13] Building libass dependencies and libass..."
cd "${BUILD_DIR}"
# freetype
if [ ! -d freetype ]; then
    git clone --depth 1 https://gitlab.freedesktop.org/freetype/freetype.git
fi
cd freetype
./autogen.sh
./configure --prefix="${PREFIX}" --enable-static --disable-shared --with-harfbuzz=no
make -j${JOBS} && make install

# harfbuzz (needed by ffmpeg drawtext in 7.x)
cd "${BUILD_DIR}"
if [ ! -d harfbuzz ]; then
    git clone --depth 1 https://github.com/harfbuzz/harfbuzz.git
fi
cd harfbuzz
PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig" \
meson setup build --prefix="${PREFIX}" --default-library=static \
    -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled \
    -Dcairo=disabled -Dicu=disabled -Dtests=disabled \
    -Ddocs=disabled -Dintrospection=disabled
ninja -C build && ninja -C build install

# Rebuild freetype with harfbuzz enabled for static linkage consistency.
cd "${BUILD_DIR}/freetype"
make clean
PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig" \
./configure --prefix="${PREFIX}" --enable-static --disable-shared --with-harfbuzz=yes
make -j${JOBS} && make install

cd "${BUILD_DIR}"
# fribidi
if [ ! -d fribidi ]; then
    git clone --depth 1 https://github.com/fribidi/fribidi.git
fi
cd fribidi
meson setup build --prefix="${PREFIX}" --default-library=static -Ddocs=false
ninja -C build && ninja -C build install
cd "${BUILD_DIR}"
# libass
if [ ! -d libass ]; then
    git clone --depth 1 https://github.com/libass/libass.git
fi
cd libass
autoreconf -fiv
PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig" \
./configure --prefix="${PREFIX}" --enable-static --disable-shared
make -j${JOBS} && make install

# --- libebur128 (EBU R128 loudness metering) ---
echo "[10/13] Building libebur128..."
cd "${BUILD_DIR}"
if [ ! -d libebur128 ]; then
    git clone --depth 1 https://github.com/jiixyj/libebur128.git
fi
mkdir -p libebur128/build && cd libebur128/build
cmake -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    ..
make -j${JOBS} && make install

# --- NVIDIA headers (for NVENC/NVDEC) ---
echo "[11/13] Installing NVIDIA codec headers..."
cd "${BUILD_DIR}"
if [ ! -d nv-codec-headers ]; then
    git clone --depth 1 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
fi
cd nv-codec-headers
make PREFIX="${PREFIX}" install

# --- VAAPI (Video Acceleration API) ---
echo "[12/13] Installing VAAPI development files..."
apt-get install -y --no-install-recommends \
    libva-dev \
    libdrm-dev \
    libvdpau-dev 2>/dev/null || true

echo "[13/13] Dependency build complete"

echo ""
echo "=== All dependencies built successfully ==="
echo "Install prefix: ${PREFIX}"
echo ""
