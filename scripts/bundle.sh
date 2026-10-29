#!/bin/sh
# Builds build/Gunner.app from the Swift package.
set -eu
cd "$(dirname "$0")/.."

APP=build/Gunner.app
VERSION=0.1.0

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Gunner"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Gunner"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Gunner</string>
  <key>CFBundleDisplayName</key><string>Gunner</string>
  <key>CFBundleIdentifier</key><string>dev.gunner.app</string>
  <key>CFBundleExecutable</key><string>Gunner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <!-- Menu bar only: no Dock icon. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# App icon from assets/icon.svg (Quick Look renders SVG; iconutil packs the sizes).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
if qlmanage -t -s 1024 -o "$ICONSET" assets/icon.svg >/dev/null 2>&1; then
  SRC="$ICONSET/icon.svg.png"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  rm "$SRC"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
rm -rf "$(dirname "$ICONSET")"

# Ad-hoc signature, so macOS will launch it and Launch at Login can register it.
codesign --force --sign - "$APP"
echo "Built $APP"
