#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"            # app/

APP_NAME="ClaudeUsageBar.app"
APP_PATH="build/$APP_NAME"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp Info.plist "$APP_PATH/Contents/"
[ -f ClaudeUsageBar.icns ] && cp ClaudeUsageBar.icns "$APP_PATH/Contents/Resources/" || true

SOURCES=$(find Sources -name '*.swift')
swiftc -parse-as-library \
    -o "$APP_PATH/Contents/MacOS/ClaudeUsageBar" \
    $SOURCES \
    -framework SwiftUI -framework AppKit -framework UserNotifications \
    -framework WidgetKit -framework ServiceManagement \
    -target arm64-apple-macos13.0

echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"
chmod 755 "$APP_PATH/Contents/MacOS/ClaudeUsageBar"
xattr -cr "$APP_PATH"
find "$APP_PATH" -name '._*' -delete 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"
echo "✅ Built $APP_PATH"

if [ "${1:-}" != "--no-open" ]; then open "$APP_PATH"; fi
