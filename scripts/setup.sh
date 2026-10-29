#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
WHISPER_COMMIT=d1be6fde11ac6e0407606b4e42fe72d34add8037

if [ "$(uname -s)" != Darwin ]; then echo "This app requires macOS." >&2; exit 1; fi
xcode-select -p >/dev/null
swift --version
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v cmake >/dev/null; then
    if ! command -v brew >/dev/null; then
        echo "Install CMake from https://cmake.org/download/ or install Homebrew, then brew install cmake." >&2
        exit 1
    fi
    brew install cmake
fi
mkdir -p vendor
if [ ! -d vendor/whisper.cpp/.git ]; then
    git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp.git vendor/whisper.cpp
fi
if [ "$(git -C vendor/whisper.cpp rev-parse HEAD)" != "$WHISPER_COMMIT" ]; then
    echo "Unexpected whisper.cpp revision; expected $WHISPER_COMMIT. Preserve your changes and use a clean vendor checkout." >&2
    exit 1
fi
if ! git -C vendor/whisper.cpp diff --quiet HEAD; then
    echo "Tracked vendor sources are modified; refusing to silently build a different engine." >&2; exit 1
fi
cmake -S Engine -B .build/engine \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=OFF
cmake --build .build/engine --config Release --target whisper-worker whisper-cli -j "${BUILD_JOBS:-6}"
"$PROJECT_DIR/scripts/download-models.sh" "$@"
echo 'Setup complete. Next: ./scripts/build-app.sh --install'
