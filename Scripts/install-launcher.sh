#!/bin/bash
# Install the vibe-pet-bridge launcher script to ~/.vibe-pet/bin/
set -e

INSTALL_DIR="$HOME/.vibe-pet/bin"
LAUNCHER="$INSTALL_DIR/vibe-pet-bridge"

mkdir -p "$INSTALL_DIR"

cat > "$LAUNCHER" << 'SCRIPT'
#!/bin/bash
# VibePet bridge launcher - finds and runs the real bridge binary

BRIDGE_NAME="vibe-pet-bridge"

# Try known locations
CANDIDATES=(
    "/Applications/VibePet.app/Contents/Helpers/$BRIDGE_NAME"
    "$HOME/Applications/VibePet.app/Contents/Helpers/$BRIDGE_NAME"
)

for candidate in "${CANDIDATES[@]}"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

# Try mdfind as fallback
APP_PATH=$(mdfind "kMDItemCFBundleIdentifier = 'com.vibe-pet.app'" 2>/dev/null | head -1)
if [ -n "$APP_PATH" ] && [ -x "$APP_PATH/Contents/Helpers/$BRIDGE_NAME" ]; then
    exec "$APP_PATH/Contents/Helpers/$BRIDGE_NAME" "$@"
fi

# Try the build directory (development)
DEV_PATH="$(dirname "$(dirname "$(dirname "$0")")")/.build/release/VibePetBridge"
if [ -x "$DEV_PATH" ]; then
    exec "$DEV_PATH" "$@"
fi

echo "[VibePet] Bridge binary not found" >&2
exit 1
SCRIPT

chmod +x "$LAUNCHER"
echo "[VibePet] Launcher installed at $LAUNCHER"
