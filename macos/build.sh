#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BgClicker"
APP_DIR="${DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

swiftc -O \
  -framework Cocoa \
  -framework Carbon \
  -framework ApplicationServices \
  "${DIR}/BgClicker.swift" \
  -o "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>BgClicker</string>
  <key>CFBundleIdentifier</key>
  <string>com.nogeo.bgclicker</string>
  <key>CFBundleName</key>
  <string>BgClicker</string>
  <key>CFBundleDisplayName</key>
  <string>后台连点器</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

# Ad-hoc 签名，便于 macOS「辅助功能」权限稳定绑定
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Build OK: ${APP_DIR}"
