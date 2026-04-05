#!/bin/bash
# Configure DMG window layout and background
set -e

VOLUME_NAME="$1"
VOLUME_PATH="/Volumes/${VOLUME_NAME}"

# Wait for volume to be ready
sleep 1

osascript <<EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 860, 600}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "${VOLUME_NAME}.app" of container window to {160, 220}
        set position of item "Applications" of container window to {500, 220}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Give Finder time to write .DS_Store
sleep 2

# Close any Finder windows for this volume
osascript -e "tell application \"Finder\" to close every window" 2>/dev/null || true
sleep 1
