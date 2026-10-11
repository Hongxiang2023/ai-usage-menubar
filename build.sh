#!/bin/bash
# Build "AI Usage.app" (a menu bar app) from source. Needs Xcode or Command Line Tools.
set -e
cd "$(dirname "$0")"
APP="AI Usage.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O MenuBarUsage.swift -o "$APP/Contents/MacOS/AIUsage"
cp collect.py "$APP/Contents/Resources/collect.py"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AI Usage</string>
<key>CFBundleIdentifier</key><string>io.github.ai-usage-menubar</string>
<key>CFBundleExecutable</key><string>AIUsage</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built: $PWD/$APP"
