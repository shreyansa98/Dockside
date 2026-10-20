#!/bin/bash
# Builds Dockside.app.
#   ./build.sh            build a universal app and install it to /Applications (or ~/Applications)
#   ./build.sh --dmg      also package build/Dockside-<version>-beta.dmg for distribution
#   ./build.sh --no-install
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.2.0"
BUILD_NUMBER="2"
APP="build/Dockside.app"
MAKE_DMG=0
INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --dmg) MAKE_DMG=1 ;;
    --no-install) INSTALL=0 ;;
  esac
done

echo "→ Compiling (arm64 + x86_64)…"
swift build -c release --arch arm64
swift build -c release --arch x86_64
mkdir -p build
lipo -create \
  .build/arm64-apple-macosx/release/Dockside \
  .build/x86_64-apple-macosx/release/Dockside \
  -output build/Dockside-universal

echo "→ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Dockside-universal "$APP/Contents/MacOS/Dockside"

if [ -f Resources/AppIcon.icns ]; then
  mkdir -p build && cp Resources/AppIcon.icns build/AppIcon.icns
fi
if [ ! -f build/AppIcon.icns ]; then
  echo "→ Rendering icon…"
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift Scripts/make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Translations: SwiftUI looks up Localizable.strings in the app bundle's .lproj folders.
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
LOCALIZATIONS=$(for d in Resources/Localization/*.lproj; do printf '<string>%s</string>' "$(basename "$d" .lproj)"; done)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dockside</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>${LOCALIZATIONS}</array>
  <key>CFBundleDisplayName</key><string>Dockside</string>
  <key>CFBundleIdentifier</key><string>app.dockside.mac</string>
  <key>CFBundleExecutable</key><string>Dockside</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Open source under the MIT License.</string>
  <key>NSAppleEventsUsageDescription</key><string>Dockside controls YouTube Music in your browser, Spotify, Music, Finder and System Events for Now Playing, Dark Mode and Empty Trash.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Dockside shows your upcoming events in the Calendar widget.</string>
  <key>NSCalendarsUsageDescription</key><string>Dockside shows your upcoming events in the Calendar widget.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>Dockside shows and completes your reminders in the Reminders widget.</string>
  <key>NSRemindersUsageDescription</key><string>Dockside shows and completes your reminders in the Reminders widget.</string>
  <key>NSMicrophoneUsageDescription</key><string>Dockside records voice memos with the Voice Memo widget.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Dockside lists your recent downloads in the Downloads widget.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Dockside shows your recent screenshots in the Screenshots widget.</string>
</dict>
</plist>
PLIST

echo "→ Signing (ad‑hoc)…"
codesign --force --deep --sign - "$APP"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  echo "→ Installing to ${DEST}…"
  pkill -x Dockside 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST/Dockside.app"
  cp -R "$APP" "$DEST/"
  echo "✓ Installed $DEST/Dockside.app"
fi

if [ "$MAKE_DMG" = 1 ]; then
  echo "→ Packaging DMG…"
  STAGE="build/dmg"
  DMG="build/Dockside-${VERSION}-beta.dmg"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cp Scripts/dmg-readme.txt "$STAGE/If macOS blocks Dockside.txt"
  hdiutil create -volname "Dockside ${VERSION} beta" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  shasum -a 256 "$DMG" | tee "$DMG.sha256"
  echo "✓ Built $DMG"
fi
