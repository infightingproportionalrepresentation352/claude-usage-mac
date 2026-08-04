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

# project.yml pins a placeholder that only the release workflow overrides, so
# without this a local build claims that version forever and nags about an
# update that is really itself.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-0.0.0}"

xcodegen generate
xcodebuild build \
    -project ClaudeUsage.xcodeproj \
    -scheme ClaudeUsage \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="$IDENTITY"

# Must not be running, or the copy replaces a live bundle.
osascript -e 'quit app "Claude Usage"' 2>/dev/null || true
rm -rf "/Applications/Claude Usage.app"
cp -R "$APP" /Applications/

echo
echo "Installed /Applications/Claude Usage.app"
open "/Applications/Claude Usage.app"

# The widget only shows up in the gallery once macOS has registered the
# extension, and a stale registration is the usual reason it doesn't.
sleep 3
echo
echo "Widget registration:"
if pluginkit -mAvvv -p com.apple.widgetkit-extension 2>/dev/null | grep -i "claude-usage.widget"; then
    echo "Registered. Add it from the widget gallery."
else
    echo "  Not registered. Try:  killall chronod"
    echo "  Still nothing? Check the extension is sandboxed and signed:"
    echo "    codesign -dv --entitlements - '/Applications/Claude Usage.app/Contents/PlugIns/ClaudeUsageWidget.appex'"
fi
