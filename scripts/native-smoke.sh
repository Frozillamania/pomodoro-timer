#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
swiftc -swift-version 5 -parse-as-library scripts/native-smoke.swift -o artifacts/native-smoke
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qa-native-pomodoro.XXXXXX")"
QA_APP="$TEST_DIR/POMODORO Timer QA.app"
ditto 'artifacts/POMODORO Timer.app' "$QA_APP"
QA_ID="local.pomodoro.qa.$(uuidgen | tr '[:upper:]' '[:lower:]')"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $QA_ID" "$QA_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName POMODORO Timer QA' "$QA_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName POMODORO Timer QA' "$QA_APP/Contents/Info.plist"
printf '%s\n' "$TEST_DIR" > artifacts/native-smoke-directory.txt
artifacts/native-smoke "$QA_APP" "$TEST_DIR" "$PWD/artifacts/native-smoke.png"
