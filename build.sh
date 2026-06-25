#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="/private/tmp/LedgerlyBuild"
APP="$BUILD/Ledgerly.app"
DMG_ROOT="$BUILD/dmg"
OUTPUT="$ROOT/../outputs"
VERSION="2.0.1"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
SDKROOT="$(DEVELOPER_DIR="$DEVELOPER_DIR" xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DMG_ROOT" "$OUTPUT"

python3 "$ROOT/make_icon.py" "$BUILD"
cp "$BUILD/AppIcon.iconset/icon_512x512@2x.png" "$APP/Contents/Resources/AppIcon.png"

DEVELOPER_DIR="$DEVELOPER_DIR" xcrun swiftc \
  -parse-as-library \
  -O \
  -target arm64-apple-macos13.0 \
  -sdk "$SDKROOT" \
  -module-cache-path "$BUILD/ModuleCache" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Security \
  -framework LinkPresentation \
  -framework CoreImage \
  -framework UserNotifications \
  "$ROOT/Sources/LedgerlyApp.swift" \
  -o "$APP/Contents/MacOS/Ledgerly"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$BUILD/Ledgerly-$VERSION.dmg" "$OUTPUT/Ledgerly-$VERSION.dmg"
hdiutil create \
  -volname "Ledgerly" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$BUILD/Ledgerly-$VERSION.dmg"
cp "$BUILD/Ledgerly-$VERSION.dmg" "$OUTPUT/Ledgerly-$VERSION.dmg"

echo "$APP"
echo "$OUTPUT/Ledgerly-$VERSION.dmg"
