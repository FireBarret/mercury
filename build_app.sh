#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Mercury"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "Building (release)…"
swift build -c release

echo "Assembling app bundle…"
rm -rf "build"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

echo "Ad-hoc signing…"
codesign --force --deep --sign - "${APP_DIR}"

echo "Done: ${APP_DIR}"
echo "Run with: open \"${APP_DIR}\""
