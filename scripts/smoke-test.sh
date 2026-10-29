#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}whisper-paste-smoke.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
# Generates a file only; does not activate the microphone or play audio.
/usr/bin/say -v Yuna -r 165 -o "$WORK_DIR/korean.aiff" \
    '오늘 회의 내용을 세 가지 항목으로 요약해 주세요. 다음 주까지 해야 할 작업과 담당자를 정리해 주세요.'
/usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 "$WORK_DIR/korean.aiff" "$WORK_DIR/korean.wav"
WHISPER_PASTE_TEST_WAV="$WORK_DIR/korean.wav" \
WHISPER_PASTE_TEST_BIN_DIR="${WHISPER_PASTE_TEST_BIN_DIR:-$PROJECT_DIR/.build/engine/bin}" swift test
