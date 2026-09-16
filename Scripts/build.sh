#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔨 Building IconDock (Release)..."
swift build -c release

BIN_PATH="$PROJECT_DIR/.build/release/IconDock"
APP_BUNDLE="$PROJECT_DIR/build/IconDock.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Packaging into $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BIN_PATH" "$MACOS_DIR/IconDock"
chmod +x "$MACOS_DIR/IconDock"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Ad-hoc sign
echo "🔏 Ad-hoc code signing IconDock.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Successfully built and packaged IconDock.app!"
echo "📍 Location: $APP_BUNDLE"
