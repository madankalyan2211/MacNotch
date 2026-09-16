#!/bin/bash
set -e

echo "🔨 Building MacBookNotch in Release mode..."
swift build -c release

APP_NAME="MacBookNotch.app"
APP_DIR="./build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating App Bundle Structure at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp .build/release/MacBookNotch "$MACOS_DIR/MacBookNotch"
cp Resources/Info.plist "$CONTENTS_DIR/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
cp Resources/AppIcon.png "$RESOURCES_DIR/AppIcon.png"

chmod +x "$MACOS_DIR/MacBookNotch"

echo "🔏 Signing App Bundle with ad-hoc signature..."
codesign --force --deep --sign - "$APP_DIR"

echo "🎨 Stamping App Icon & registering with LaunchServices..."
swift -e "import AppKit; if let img = NSImage(contentsOfFile: \"Resources/AppIcon.icns\") { NSWorkspace.shared.setIcon(img, forFile: \"$APP_DIR\", options: []) }"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" || true

echo "✅ App bundle created successfully: $APP_DIR"
echo "🚀 To run: open $APP_DIR or .build/release/MacBookNotch"
