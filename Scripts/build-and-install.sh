#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VibePet.app"
SOURCE_APP="$ROOT_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

cd "$ROOT_DIR"

echo "[VibePet] Building app bundle..."
make bundle

if pgrep -x "VibePet" >/dev/null 2>&1; then
  echo "[VibePet] Quitting running app..."
  osascript -e 'tell application "VibePet" to quit' >/dev/null 2>&1 || true
  sleep 1
fi

echo "[VibePet] Installing to $TARGET_APP ..."
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

echo "[VibePet] Launching installed app..."
open "$TARGET_APP"

echo "[VibePet] Done."
