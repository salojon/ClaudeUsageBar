#!/bin/bash
set -e

APP_NAME="ClaudeUsageBar"
BUNDLE_ID="com.jonathansela.ClaudeUsageBar"
VERSION="1.0.0"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "🔨 Building ${APP_NAME}..."
swift build -c release 2>&1

BINARY=".build/release/${APP_NAME}"

echo "📦 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$CONTENTS/Resources"

cp "$BINARY" "$MACOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026</string>
</dict>
</plist>
EOF

echo "✍️  Signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Done! App installed at: $APP_BUNDLE"
echo ""
echo "To launch:  open '$APP_BUNDLE'"
echo "To rebuild: bash build.sh"
