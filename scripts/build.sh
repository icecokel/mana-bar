#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/module-cache .build/ManaBar.app/Contents/MacOS .build/ManaBar.app/Contents/Resources/Fonts
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"

swiftc -swift-version 6 -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/module-cache \
  -framework AppKit -framework Security \
  Sources/*.swift -o .build/ManaBar.app/Contents/MacOS/ManaBar

cp Assets/*.png Assets/CREDITS.txt .build/ManaBar.app/Contents/Resources/
cp Assets/Fonts/* .build/ManaBar.app/Contents/Resources/Fonts/

cat > .build/ManaBar.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ManaBar</string>
  <key>CFBundleIdentifier</key><string>app.manabar.prototype</string>
  <key>CFBundleName</key><string>ManaBar</string>
  <key>CFBundleDisplayName</key><string>ManaBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>Fonts/</string>
</dict></plist>
PLIST

./scripts/sign.sh .build/ManaBar.app

printf 'Built %s/.build/ManaBar.app\n' "$PWD"
