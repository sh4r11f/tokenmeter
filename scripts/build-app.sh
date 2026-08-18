#!/usr/bin/env bash
# Assembles dist/TokenMeter.app from a release swift build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

APP_DIR="dist/TokenMeter.app"
CONTENTS="$APP_DIR/Contents"

rm -rf dist
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/TokenMeter" "$CONTENTS/MacOS/TokenMeter"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/statusline.sh "$CONTENTS/Resources/statusline.sh"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
fi

echo "Built $APP_DIR"
