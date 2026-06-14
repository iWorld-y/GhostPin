#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="$ROOT_DIR/Sources/TodoPin/Resources/Models"
MODEL_NAME="ggml-base-q5_1.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME"
EXPECTED_SHA256="422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

mkdir -p "$MODEL_DIR"

if [[ -f "$MODEL_PATH" ]]; then
  ACTUAL_SHA256="$(shasum -a 256 "$MODEL_PATH" | awk '{print $1}')"
  if [[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]]; then
    echo "$MODEL_NAME already exists and checksum matches."
    exit 0
  fi
  echo "Existing $MODEL_NAME checksum mismatch; replacing it." >&2
  rm -f "$MODEL_PATH"
fi

TMP_PATH="$MODEL_PATH.tmp"
curl -L --fail -o "$TMP_PATH" "$MODEL_URL"
ACTUAL_SHA256="$(shasum -a 256 "$TMP_PATH" | awk '{print $1}')"

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  rm -f "$TMP_PATH"
  echo "Checksum mismatch for $MODEL_NAME" >&2
  echo "expected: $EXPECTED_SHA256" >&2
  echo "actual:   $ACTUAL_SHA256" >&2
  exit 1
fi

mv "$TMP_PATH" "$MODEL_PATH"
echo "Downloaded $MODEL_NAME"
