#!/bin/bash
set -euo pipefail

MODEL_DIR="$HOME/Library/Application Support/WhisperPaste/models"
REVISION=5359861c739e955e79d9a303bcbc70fb988958b1
mkdir -p "$MODEL_DIR"
chmod 700 "$MODEL_DIR"
if [ "$#" -eq 0 ]; then set -- small medium; fi

for model in "$@"; do
    case "$model" in
        small) expected=1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b ;;
        medium) expected=6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208 ;;
        *) echo "Supported models: small medium (multilingual)" >&2; exit 2 ;;
    esac
    destination="$MODEL_DIR/ggml-$model.bin"
    if [ -f "$destination" ] && printf '%s  %s\n' "$expected" "$destination" | shasum -a 256 -c - >/dev/null 2>&1; then
        echo "Already verified: $destination"
        continue
    fi
    echo "Downloading multilingual $model to $destination"
    curl --fail --location --retry 3 --connect-timeout 30 --continue-at - \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/$REVISION/ggml-$model.bin" \
        --output "$destination.partial"
    if ! printf '%s  %s\n' "$expected" "$destination.partial" | shasum -a 256 -c -; then
        echo "Checksum mismatch. Inspect/remove $destination.partial before retrying." >&2
        exit 1
    fi
    chmod 600 "$destination.partial"
    mv "$destination.partial" "$destination"
done
