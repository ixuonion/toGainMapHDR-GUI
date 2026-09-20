#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GainMapHDR"
BUNDLE_ID="dev.codex.GainMapHDR"
MIN_SYSTEM_VERSION="27.0"
BUILD_CONFIGURATION="${GAINMAP_BUILD_CONFIGURATION:-release}"
if [[ "$MODE" == "debug" || "$MODE" == "--debug" ]]; then
  BUILD_CONFIGURATION="${GAINMAP_BUILD_CONFIGURATION:-debug}"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
BACKEND_SOURCE="$ROOT_DIR/Sources/GainMapHDRApp/Resources/backend"
APP_ICON_SOURCE="$ROOT_DIR/Sources/GainMapHDRApp/Resources/AppIcon.icns"
RESOURCE_BUNDLE_NAME="${APP_NAME}_GainMapHDRApp.bundle"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

# Do not kill an app that may own running conversions.
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "Quit $APP_NAME normally before replacing its bundle (conversion cleanup must finish)." >&2
  exit 1
fi

swift build -c "$BUILD_CONFIGURATION" --scratch-path "$ROOT_DIR/.build"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --scratch-path "$ROOT_DIR/.build" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
find "$(dirname "$BUILD_BINARY")" -maxdepth 1 -name "${APP_NAME}_*.bundle" -exec cp -R {} "$APP_RESOURCES/" \;
cp -R "$BACKEND_SOURCE" "$APP_RESOURCES/backend"
chmod +x "$APP_RESOURCES/backend/toGainMapHDR"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
# Privacy prompts resolve localized purpose strings from the main app, not the SwiftPM resource bundle.
for language in en zh-Hans; do
  mkdir -p "$APP_RESOURCES/$language.lproj"
  cp "$ROOT_DIR/Sources/GainMapHDRApp/Resources/$language.lproj/InfoPlist.strings" "$APP_RESOURCES/$language.lproj/InfoPlist.strings"
done
mkdir -p "$APP_RESOURCES/licenses"
cp "$ROOT_DIR/.build/checkouts/swift-subprocess/LICENSE" "$APP_RESOURCES/licenses/swift-subprocess.txt"
cp "$ROOT_DIR/.build/checkouts/swift-system/LICENSE.txt" "$APP_RESOURCES/licenses/swift-system.txt"

if [[ ! -d "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME" ]]; then
  echo "missing SwiftPM resource bundle: $RESOURCE_BUNDLE_NAME" >&2
  exit 1
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>2.1.0</string>
  <key>CFBundleVersion</key>
  <string>210</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Images</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.image</string></array>
  </dict></array>
  <key>NSPhotoLibraryAddUsageDescription</key>
  <string>GainMapHDR adds your converted HEIC photos to Photos Library, preserving HDR, Gain Map, color, and metadata.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    echo "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
