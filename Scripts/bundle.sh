#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Presence

APP="Presence.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Presence "$APP/Contents/MacOS/Presence"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Presence</string>
    <key>CFBundleIdentifier</key>
    <string>com.rootless.presence</string>
    <key>CFBundleName</key>
    <string>Presence</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature by default. Every ad-hoc rebuild changes the cdhash and
# revokes the Accessibility permission already granted — expected during
# development. Set DEV_ID="Developer ID Application: ..." for a stable identity.
SIGNING_IDENTITY="${DEV_ID:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"

echo "done: $APP (signed with '$SIGNING_IDENTITY')"
