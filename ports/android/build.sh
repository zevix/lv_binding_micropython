#!/usr/bin/env bash
#
# Build an Android APK running MicroPython + LVGL on top of SDL2.
#
# The MicroPython unix port (VARIANT=lvgl) is cross-compiled with the Android
# NDK as libmain.so, and packaged with libSDL2.so and SDL's Java activity.
#
# Requirements: Android SDK + NDK, JDK 17, cmake, python3.
#
# Environment:
#   MPY_DIR           lv_micropython checkout with this repository at
#                     user_modules/lv_binding_micropython (default: autodetect)
#   ANDROID_NDK_HOME  Android NDK path (ANDROID_NDK_LATEST_HOME also accepted)
#   ABIS              ABIs to build (default: "arm64-v8a armeabi-v7a x86_64")
#   ANDROID_API       minimum API level (default: 28, needed for getrandom())
#   SDL_VERSION       SDL2 release to use (default: 2.32.10)
#   BUILD_DIR         work directory (default: $MPY_DIR/ports/unix/build-android)
#
# Output: $BUILD_DIR/lvgl-micropython.apk (debug signed)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPY_DIR="${MPY_DIR:-$(cd "$HERE/../../../.." && pwd)}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
ABIS="${ABIS:-arm64-v8a armeabi-v7a x86_64}"
ANDROID_API="${ANDROID_API:-28}"
SDL_VERSION="${SDL_VERSION:-2.32.10}"
BUILD_DIR="${BUILD_DIR:-$MPY_DIR/ports/unix/build-android}"
JOBS="$(nproc)"

if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
    echo "Set ANDROID_NDK_HOME to the Android NDK directory" >&2
    exit 1
fi
if [ ! -f "$MPY_DIR/ports/unix/Makefile" ]; then
    echo "MPY_DIR ($MPY_DIR) is not a MicroPython checkout" >&2
    exit 1
fi

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
mkdir -p "$BUILD_DIR"

# SDL2 sources (native library and Java activity)
SDL_SRC="$BUILD_DIR/SDL2-$SDL_VERSION"
if [ ! -d "$SDL_SRC" ]; then
    curl -sSfL "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz" \
        | tar xz -C "$BUILD_DIR"
fi

# mpy-cross runs on the host, build it before CC is overridden
make -C "$MPY_DIR/mpy-cross" -j "$JOBS"

PROJECT="$BUILD_DIR/android-project"
rm -rf "$PROJECT"
cp -r "$SDL_SRC/android-project" "$PROJECT"
rm -rf "$PROJECT/app/jni"
cp -r "$HERE/app/." "$PROJECT/app/"
mkdir -p "$PROJECT/app/src/main/assets"
cp "$HERE/main.py" "$PROJECT/app/src/main/assets/"

for ABI in $ABIS; do
    case "$ABI" in
        arm64-v8a) TRIPLE=aarch64-linux-android ;;
        armeabi-v7a) TRIPLE=armv7a-linux-androideabi ;;
        x86_64) TRIPLE=x86_64-linux-android ;;
        x86) TRIPLE=i686-linux-android ;;
        *) echo "Unknown ABI $ABI" >&2; exit 1 ;;
    esac
    echo "=== Building $ABI ==="

    SDL_BUILD="$BUILD_DIR/sdl-$ABI"
    SDL_PREFIX="$SDL_BUILD/install"
    cmake -S "$SDL_SRC" -B "$SDL_BUILD" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_API" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$SDL_PREFIX" \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF
    cmake --build "$SDL_BUILD" -j "$JOBS"
    cmake --install "$SDL_BUILD"

    # pkg-config file used by micropython.mk. PKG_CONFIG_LIBDIR also hides the
    # host's freetype/rlottie, which can't be linked into an Android library.
    PC_DIR="$SDL_BUILD/pkgconfig"
    mkdir -p "$PC_DIR"
    cat > "$PC_DIR/sdl2.pc" <<EOF
Name: sdl2
Description: SDL2 for Android $ABI
Version: $SDL_VERSION
Cflags: -I$SDL_PREFIX/include -I$SDL_PREFIX/include/SDL2 -D_REENTRANT
Libs: -L$SDL_PREFIX/lib -lSDL2
EOF

    MPY_BUILD="build-android-$ABI"
    PKG_CONFIG_LIBDIR="$PC_DIR" PKG_CONFIG_PATH="" make -C "$MPY_DIR/ports/unix" -j "$JOBS" \
        VARIANT=lvgl \
        BUILD="$MPY_BUILD" \
        PROG=libmain.so \
        LV_ANDROID=1 \
        CC="$TOOLCHAIN/bin/$TRIPLE$ANDROID_API-clang" \
        STRIP="$TOOLCHAIN/bin/llvm-strip" \
        SIZE="$TOOLCHAIN/bin/llvm-size" \
        CWARN="-Wall -Wno-unused-parameter -Wno-unused-function" \
        LDFLAGS_ARCH="-Wl,--gc-sections" \
        MICROPY_PY_FFI=0 \
        MICROPY_PY_SSL=0 \
        MICROPY_PY_BTREE=0 \
        MICROPY_PY_THREAD=0

    JNI_LIBS="$PROJECT/app/src/main/jniLibs/$ABI"
    mkdir -p "$JNI_LIBS"
    cp "$SDL_PREFIX/lib/libSDL2.so" "$JNI_LIBS/"
    cp "$MPY_DIR/ports/unix/$MPY_BUILD/libmain.so" "$JNI_LIBS/"
done

(cd "$PROJECT" && ./gradlew --no-daemon assembleDebug)
cp "$PROJECT/app/build/outputs/apk/debug/app-debug.apk" "$BUILD_DIR/lvgl-micropython.apk"
echo "APK: $BUILD_DIR/lvgl-micropython.apk"
