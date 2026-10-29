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
swift build -c release --product ron
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p dist
STAGING="$(mktemp -d "$PROJECT_DIR/dist/.bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/ron.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN_DIR/ron" "$APP/Contents/MacOS/ron"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/ko.lproj "$APP/Contents/Resources/"
cp -R "$BIN_DIR/WhisperPaste_WhisperPasteCore.bundle" "$APP/Contents/Resources/"
cp "$ENGINE" "$APP/Contents/Resources/bin/whisper-cli"
cp "$WORKER" "$APP/Contents/Resources/bin/whisper-worker"
cp TUTORIAL.ko.md "$APP/Contents/Resources/TUTORIAL.ko.md"
cp TUTORIAL.en.md "$APP/Contents/Resources/TUTORIAL.en.md"
cp README.md "$APP/Contents/Resources/README.md"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp vendor/whisper.cpp/LICENSE "$APP/Contents/Resources/whisper.cpp-LICENSE.txt"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Resources/bin/whisper-cli"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Resources/bin/whisper-worker"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
ditto "$APP" "$PROJECT_DIR/dist/ron.app"
rm -f "$PROJECT_DIR/dist/ron.app/Contents/Resources/PERFORMANCE.ko.md"
echo "Built: $PROJECT_DIR/dist/ron.app"
if [ "${1:-}" = --install ]; then
    DEST="$HOME/Applications/ron.app"
    LEGACY_INSTALLED=("$HOME/Applications/sacho.app" "$HOME/Applications/Whisper Paste.app")
    LEGACY_BUILDS=("$PROJECT_DIR/dist/sacho.app" "$PROJECT_DIR/dist/Whisper Paste.app")
    for candidate in "$DEST" "${LEGACY_INSTALLED[@]}" "${LEGACY_BUILDS[@]}"; do
        if [ -e "$candidate" ]; then
            bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$candidate/Contents/Info.plist")
            if [ "$bundle_id" != io.github.sungho-ham.whisper-paste ]; then
                echo "Refusing to overwrite or migrate another app: $candidate" >&2; exit 1
            fi
        fi
        for executable in ron sacho WhisperPaste; do
            if pgrep -f "$candidate/Contents/MacOS/$executable" >/dev/null; then
                echo 'Quit the running ron / sacho / Whisper Paste app before installing an update.' >&2; exit 1
            fi
        done
    done
    mkdir -p "$HOME/Applications"
    if [ ! -e "$DEST" ]; then
        for legacy in "${LEGACY_INSTALLED[@]}"; do
            if [ -d "$legacy" ]; then
                # Back up the original, then rename it so filesystem bookmarks
                # can follow the installed copy to its new app name.
                BACKUP="$(mktemp -d "$PROJECT_DIR/.build/legacy-app.XXXXXX")"
                LEGACY_NAME="$(basename "$legacy")"
                ditto "$legacy" "$BACKUP/$LEGACY_NAME"
                mv "$legacy" "$DEST"
                echo "Previous app backed up: $BACKUP/$LEGACY_NAME"
                break
            fi
        done
    fi
    ditto "$APP" "$DEST"
    rm -f "$DEST/Contents/Resources/PERFORMANCE.ko.md"
    # ditto merges bundles; discard executables left by earlier app names.
    for executable in sacho WhisperPaste; do
        if [ -f "$DEST/Contents/MacOS/$executable" ]; then
            rm "$DEST/Contents/MacOS/$executable"
        fi
    done
    codesign --verify --deep --strict "$DEST"
    for legacy in "${LEGACY_INSTALLED[@]}" "${LEGACY_BUILDS[@]}"; do
        if [ -d "$legacy" ]; then
            BACKUP="$(mktemp -d "$PROJECT_DIR/.build/legacy-app.XXXXXX")"
            LEGACY_NAME="$(basename "$legacy")"
            mv "$legacy" "$BACKUP/$LEGACY_NAME"
            echo "Previous app archived: $BACKUP/$LEGACY_NAME"
        fi
    done
    echo "Installed: $DEST"
    echo 'Open with: open "$HOME/Applications/ron.app"'
fi
