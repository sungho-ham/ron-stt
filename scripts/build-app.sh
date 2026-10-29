#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
ENGINE="$PROJECT_DIR/.build/engine/bin/whisper-cli"
WORKER="$PROJECT_DIR/.build/engine/bin/whisper-worker"
if [ ! -x "$ENGINE" ] || [ ! -x "$WORKER" ]; then echo 'Run ./scripts/setup.sh first.' >&2; exit 1; fi
SIGNING_CONFIG="$HOME/Library/Application Support/WhisperPaste/signing.plist"
SIGN_ARGS=(--force --timestamp=none)
if [ -f "$SIGNING_CONFIG" ]; then
    IDENTITY=$(/usr/libexec/PlistBuddy -c 'Print Identity' "$SIGNING_CONFIG")
    KEYCHAIN=$(/usr/libexec/PlistBuddy -c 'Print Keychain' "$SIGNING_CONFIG")
    SIGN_ARGS+=(--sign "$IDENTITY" --keychain "$KEYCHAIN")
    echo "Using persistent signing identity: $IDENTITY"
else
    SIGN_ARGS+=(--sign -)
    echo 'Using ad-hoc signing. Run ./scripts/setup-signing.sh for a persistent local identity.'
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p dist
STAGING="$(mktemp -d "$PROJECT_DIR/dist/.bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Whisper Paste.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN_DIR/WhisperPaste" "$APP/Contents/MacOS/WhisperPaste"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/ko.lproj "$APP/Contents/Resources/"
cp -R "$BIN_DIR/WhisperPaste_WhisperPasteCore.bundle" "$APP/Contents/Resources/"
cp "$ENGINE" "$APP/Contents/Resources/bin/whisper-cli"
cp "$WORKER" "$APP/Contents/Resources/bin/whisper-worker"
cp TUTORIAL.ko.md "$APP/Contents/Resources/TUTORIAL.ko.md"
cp TUTORIAL.en.md "$APP/Contents/Resources/TUTORIAL.en.md"
cp PERFORMANCE.ko.md "$APP/Contents/Resources/PERFORMANCE.ko.md"
cp README.md "$APP/Contents/Resources/README.md"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp vendor/whisper.cpp/LICENSE "$APP/Contents/Resources/whisper.cpp-LICENSE.txt"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Resources/bin/whisper-cli"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Resources/bin/whisper-worker"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
ditto "$APP" "$PROJECT_DIR/dist/Whisper Paste.app"
echo "Built: $PROJECT_DIR/dist/Whisper Paste.app"
if [ "${1:-}" = --install ]; then
    DEST="$HOME/Applications/Whisper Paste.app"
    if pgrep -f "$DEST/Contents/MacOS/WhisperPaste" >/dev/null; then
        echo 'Quit the running Whisper Paste app before installing an update.' >&2; exit 1
    fi
    if [ -d "$DEST" ]; then
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
        if [ "$bundle_id" != io.github.sungho-ham.whisper-paste ]; then
            echo "Refusing to overwrite another app: $DEST" >&2; exit 1
        fi
    fi
    mkdir -p "$HOME/Applications"
    ditto "$APP" "$DEST"
    codesign --verify --deep --strict "$DEST"
    echo "Installed: $DEST"
    echo 'Open with: open "$HOME/Applications/Whisper Paste.app"'
fi
