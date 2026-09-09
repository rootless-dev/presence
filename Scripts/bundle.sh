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

# Ad-hoc por padrão. Cada rebuild ad-hoc muda o cdhash e revoga a permissão de
# Acessibilidade já concedida — esperado durante o desenvolvimento. Defina
# DEV_ID="Developer ID Application: ..." para uma identidade estável.
SIGNING_IDENTITY="${DEV_ID:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"

echo "pronto: $APP (assinado com '$SIGNING_IDENTITY')"
