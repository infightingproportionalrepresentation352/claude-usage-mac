#!/usr/bin/env bash
# Build Claude Usage.app and install it to /Applications.
#
# Signs ad-hoc by default, which is enough to run it yourself. To sign with your
# own identity (needed for "Open at login" to stick):
#
#   CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
#
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || {
    echo "xcodegen is required:  brew install xcodegen" >&2
    exit 1
}

IDENTITY="${CODE_SIGN_IDENTITY:--}"
DERIVED=".build-xcode"
APP="$DERIVED/Build/Products/Release/Claude Usage.app"

xcodegen generate
xcodebuild build \
    -project ClaudeUsage.xcodeproj \
    -scheme ClaudeUsage \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$IDENTITY"

# Must not be running, or the copy replaces a live bundle.
osascript -e 'quit app "Claude Usage"' 2>/dev/null || true
rm -rf "/Applications/Claude Usage.app"
cp -R "$APP" /Applications/

echo
echo "Installed /Applications/Claude Usage.app"
echo "The widget appears in the widget gallery once the app has run at least once."
open "/Applications/Claude Usage.app"
