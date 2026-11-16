#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="${POMODORO_ARTIFACTS_DIR:-artifacts}/POMODORO Timer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/POMODORO.icns Assets/MenuBarIcon.png "$APP/Contents/Resources/"
cp "$BIN_DIR/PomodoroTimer" "$APP/Contents/MacOS/POMODORO.new"
mv -f "$APP/Contents/MacOS/POMODORO.new" "$APP/Contents/MacOS/POMODORO"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>POMODORO</string>
<key>CFBundleIdentifier</key><string>local.pomodoro.timer</string>
<key>CFBundleName</key><string>POMODORO Timer</string>
<key>CFBundleDisplayName</key><string>POMODORO Timer</string>
<key>CFBundleIconFile</key><string>POMODORO</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf '%s\n' "Built unsigned $APP (not installed or launched)"
