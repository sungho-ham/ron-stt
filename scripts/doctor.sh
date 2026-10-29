#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/ron.app}"
MODEL_DIR="$HOME/Library/Application Support/WhisperPaste/models"
failed=0
check() { if "$@"; then echo '  OK'; else echo '  FAILED'; failed=1; fi; }
echo "macOS $(sw_vers -productVersion), $(uname -m)"
echo "App: $APP"
check test -x "$APP/Contents/MacOS/ron"
check codesign --verify --deep --strict "$APP"
echo 'Embedded whisper.cpp:'
check test -x "$APP/Contents/Resources/bin/whisper-cli"
check test -x "$APP/Contents/Resources/bin/whisper-worker"
echo 'Small model checksum:'
if ! printf '%s  %s\n' 1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b "$MODEL_DIR/ggml-small.bin" | shasum -a 256 -c -; then failed=1; fi
echo 'Medium model checksum:'
if ! printf '%s  %s\n' 6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208 "$MODEL_DIR/ggml-medium.bin" | shasum -a 256 -c -; then failed=1; fi
echo 'Manually check microphone and Accessibility permissions in System Settings.'
echo "Tutorial: $PROJECT_DIR/TUTORIAL.ko.md"
exit "$failed"
