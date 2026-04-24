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

echo "[VibePet] Building and signing app bundle..."
# 走 sign 而不是 bundle，让 Makefile 用稳定的 codesigning identity 签名，避免 ad-hoc
# CDHash 每次变动导致 TCC 授权反复失效（Documents/自动化控制等权限每次装都弹窗）。
make sign

if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
  echo "[VibePet] Stopping running app..."
  # 用 SIGTERM 而不是 osascript，避免每次触发 "Terminal wants to control VibePet" 的
  # 自动化权限弹窗 —— ad-hoc 签名的 CDHash 每次构建都会变，TCC 记录总是失效。
  pkill -TERM -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true
  if ! wait_for_app_exit; then
    echo "[VibePet] TERM timed out, sending KILL..."
    pkill -KILL -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true
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
