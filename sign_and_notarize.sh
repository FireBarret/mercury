#!/bin/bash
# Builds Mercury, signs it with a Developer ID Application cert (hardened runtime),
# notarizes it with Apple, staples the ticket, and packages it as a DMG.
#
# One-time setup:
#   1. Install a "Developer ID Application" cert (Xcode > Settings > Accounts >
#      Manage Certificates > + > Developer ID Application).
#   2. Store notarization credentials in the keychain:
#        xcrun notarytool store-credentials mercury-notary \
#          --apple-id shaban.dariush@gmail.com --team-id 6FX577RXQP
#      (it prompts for an app-specific password from appleid.apple.com)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Mercury"
APP_DIR="build/${APP_NAME}.app"
ZIP="build/${APP_NAME}-notarize.zip"
PROFILE="${NOTARY_PROFILE:-mercury-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"

if [ -z "${IDENTITY}" ]; then
    echo "No 'Developer ID Application' identity found in the keychain." >&2
    exit 1
fi

./build_app.sh

echo "Signing with: ${IDENTITY}"
codesign --force --deep --options runtime --timestamp --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Notarizing…"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP}"
xcrun notarytool submit "${ZIP}" --keychain-profile "${PROFILE}" --wait

echo "Stapling…"
xcrun stapler staple "${APP_DIR}"
spctl --assess --type execute --verbose "${APP_DIR}"

rm -f "${ZIP}"

echo "Building DMG…"
DMG="build/${APP_NAME}.dmg"
STAGE="$(mktemp -d)"
cp -R "${APP_DIR}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"
codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
xcrun notarytool submit "${DMG}" --keychain-profile "${PROFILE}" --wait
xcrun stapler staple "${DMG}"
spctl --assess --type open --context context:primary-signature --verbose "${DMG}"
echo "Done: ${DMG}"
