#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VibePet.app"
APP_PROCESS_NAME="VibePet"
SOURCE_APP="$ROOT_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

wait_for_app_exit() {
  local i
  for ((i = 0; i < 20; i++)); do
    if ! pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

wait_for_app_launch() {
  local i
  for ((i = 0; i < 20; i++)); do
    if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

cd "$ROOT_DIR"

echo "[VibePet] Building app bundle..."
make bundle

if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
  echo "[VibePet] Quitting running app..."
  osascript -e 'tell application "VibePet" to quit' >/dev/null 2>&1 || true
  if ! wait_for_app_exit; then
    echo "[VibePet] Graceful quit timed out, sending TERM..."
    pkill -TERM -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true
    wait_for_app_exit || {
      echo "[VibePet] Failed to stop running app." >&2
      exit 1
    }
  fi
fi

echo "[VibePet] Installing to $TARGET_APP ..."
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

echo "[VibePet] Launching installed app..."
open -na "$TARGET_APP"
wait_for_app_launch || {
  echo "[VibePet] App did not relaunch after install." >&2
  exit 1
}

echo "[VibePet] Done."
