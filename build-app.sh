#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PrismShift"
OUTPUT_DIR="$ROOT/outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/release/PrismShift"

cd "$ROOT"
mkdir -p "$(dirname "$EXECUTABLE")"
swiftc Sources/PrismShift/*.swift \
  -swift-version 5 \
  -module-cache-path "$ROOT/.build/ModuleCache" \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$EXECUTABLE" \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework ImageIO \
  -framework PDFKit

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/PrismShift"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>PrismShift</string>
  <key>CFBundleIdentifier</key>
  <string>local.prismshift.app</string>
  <key>CFBundleName</key>
  <string>PrismShift</string>
  <key>CFBundleDisplayName</key>
  <string>PrismShift</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Files to convert</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.data</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "$APP_DIR"
